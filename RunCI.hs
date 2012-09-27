{-# LANGUAGE BangPatterns, GeneralizedNewtypeDeriving, StandaloneDeriving #-}

import           Options.Applicative    
import           Data.Monoid ((<>))                 
import           System.FilePath.Posix ((</>))

import           Data.Vector (Vector)    
import qualified Data.Vector.Generic as V    
import           Statistics.Sample (mean)       

import qualified Data.Bimap as BM                 
import qualified Data.Set as S
import           Data.Set (Set)
import qualified Data.Map as M
import           Data.Maybe (mapMaybe)       

import           Control.Applicative
import           BayesStack.Models.Topic.CitationInfluence

import           Data.Char (isAlpha)                 
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import           Data.Text.Read (decimal)
       
import           Data.Random
import           System.Random.MWC                 

import           Text.Printf
                 
newtype Node = Node Int deriving (Show, Eq, Ord)
       
data RunCIOpts = RunCIOpts { arcsFile        :: FilePath
                           , nodeItemsFile   :: FilePath
                           , stopwords       :: Maybe FilePath
                           }

runCIOpts = RunCIOpts 
    <$> strOption ( long "arcs"
                  & metavar "FILE"
                  & value "arcs"
                  & help "File containing arcs"
                  )
    <*> strOption ( long "items"
                  & metavar "FILE"
                  & value "node-items"
                  & help "File containing nodes' items"
                  )
    <*> nullOption ( long "stopwords"
                   & metavar "FILE"
                   & reader (Just . Just)
                   & value (Just "stopwords.txt")
                   & help "Stop words list"
                   )

readArcs :: FilePath -> IO (Set Arc)
readArcs fname =
    S.fromList . mapMaybe parseLine . T.lines <$> TIO.readFile fname
    where parseLine :: T.Text -> Maybe Arc
          parseLine l = case T.words l of
             [a,b] -> case (decimal a, decimal b) of
                          (Right (a',_), Right (b',_)) ->
                              Just $ Arc (CitingNode a', CitedNode b')
                          otherwise -> Nothing
             otherwise -> Nothing

type Term = T.Text
readAbstracts :: Set Term -> FilePath -> IO (M.Map Node (Set Term))
readAbstracts stopWords fname =
    M.unionsWith S.union . map parseLine . T.lines <$> TIO.readFile fname
    where parseLine :: T.Text -> M.Map Node (Set Term)
          parseLine l = case T.words l of
             n:words | Right (n',_) <- decimal n ->
                 M.singleton (Node n')
                 $ S.fromList
                 $ filter (\word->T.length word > 4)
                 $ map (T.filter isAlpha)
                 $ filter (`S.notMember` stopWords) words
             otherwise -> M.empty

netData :: M.Map Node (Set Term) -> Set Arc -> Int -> NetData
netData abstracts arcs nTopics = 
    let items :: BM.Bimap Item Term
        items = BM.fromList $ zip [Item i | i <- [1..]] (S.toList $ S.unions $ M.elems abstracts)
    in NetData { dAlphaPsi         = 0.1
               , dAlphaLambda      = 0.1
               , dAlphaPhi         = 0.1
               , dAlphaOmega       = 0.1
               , dAlphaGammaShared = 0.8
               , dAlphaGammaOwn    = 0.2
               , dArcs             = arcs
               , dItems            = S.fromList $ BM.keys items
               , dTopics           = S.fromList [Topic i | i <- [1..nTopics]]
               , dCitedNodeItems   = M.fromList
                                     $ zip [CitedNI i | i <- [0..]]
                                     $ do (Node n,terms) <- M.assocs abstracts
                                          term <- S.toList terms
                                          return (CitedNode n, items BM.!> term)
               , dCitingNodeItems  = M.fromList
                                     $ zip [CitingNI i | i <- [0..]]
                                     $ do (Node n,terms) <- M.assocs abstracts
                                          term <- S.toList terms
                                          return (CitingNode n, items BM.!> term)
               }
            
opts = info (runCIOpts)
           (  fullDesc
           <> progDesc "Learn citation influence model"
           <> header "run-ci - learn citation influence model"
           )

main = do
    args <- execParser $ opts
    stopWords <- case stopwords args of
                     Just f  -> S.fromList . T.words <$> TIO.readFile f
                     Nothing -> return S.empty
    printf "Read %d stopwords\n" (S.size stopWords)

    arcs <- readArcs $ arcsFile args
    abstracts <- readAbstracts stopWords $ nodeItemsFile args
    let termCounts = V.fromListN (M.size abstracts) $ map S.size $ M.elems abstracts :: Vector Int
    printf "Read %d arcs, %d abstracts\n" (S.size arcs) (M.size abstracts)
    printf "Mean terms per document:  %1.2f\n" (mean $ V.map realToFrac termCounts)
    
    withSystemRandom $ \mwc->do
    let nd = netData abstracts arcs 10
    init <- runRVar (randomInitialize nd) mwc
    let m = model nd init
    print $ modelLikelihood m
