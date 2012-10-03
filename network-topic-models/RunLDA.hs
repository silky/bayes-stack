{-# LANGUAGE BangPatterns, GeneralizedNewtypeDeriving, StandaloneDeriving #-}

import           Prelude hiding (mapM)    

import           Options.Applicative    
import           Data.Monoid ((<>))                 
import           Control.Monad (liftM)

import           Data.Vector (Vector)    
import qualified Data.Vector.Generic as V    
import           Statistics.Sample (mean)       

import           Data.Traversable (mapM)                 
import qualified Data.Set as S
import           Data.Set (Set)
import qualified Data.Map.Strict as M

import           ReadData       
import qualified RunSampler as Sampler
import           BayesStack.DirMulti
import           BayesStack.Models.Topic.LDA
import           BayesStack.UniqueKey

import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
       
import           System.FilePath.Posix ((</>))
import           Data.Serialize
import qualified Data.ByteString as BS

import           Data.Random
import           System.Random.MWC                 

import           Text.Printf
                 
data RunOpts = RunOpts { nodesFile       :: FilePath
                       , stopwords       :: Maybe FilePath
                       , nTopics         :: Int
                       , samplerOpts     :: Sampler.SamplerOpts
                       }

runOpts :: Parser RunOpts
runOpts = RunOpts 
    <$> strOption  ( long "nodes"
                  <> short 'n'
                  <> metavar "FILE"
                  <> help "File containing nodes and their associated items"
                   )
    <*> nullOption ( long "stopwords"
                  <> short 's'
                  <> metavar "FILE"
                  <> reader (Just . Just)
                  <> value Nothing
                  <> help "Stop word list"
                   )
    <*> option     ( long "topics"
                  <> short 't'
                  <> metavar "N"
                  <> value 20
                  <> help "Number of topics"
                   )
    <*> Sampler.samplerOpts
    
termsToItems :: M.Map Node [Term] -> (M.Map Node [Item], M.Map Item Term)
termsToItems = runUniqueKey' [Item i | i <- [0..]]
            . mapM (mapM getUniqueKey)

netData :: M.Map Node [Item] -> Int -> NetData
netData nodeItems nTopics = 
    NetData { dAlphaTheta       = 0.1
            , dAlphaPhi         = 0.1
            , dItems            = S.unions $ map S.fromList $ M.elems nodeItems
            , dTopics           = S.fromList [Topic i | i <- [1..nTopics]]
            , dNodeItems        = M.fromList
                                  $ zip [NodeItem i | i <- [0..]]
                                  $ do (n,items) <- M.assocs nodeItems
                                       item <- items
                                       return (n, item)
            , dNodes            = M.keysSet nodeItems
            }
            
opts :: ParserInfo RunOpts
opts = info runOpts (  fullDesc
                    <> progDesc "Learn LDA model"
                    <> header "run-lda - learn LDA model"
                    )

instance Sampler.SamplerModel MState where
    estimateHypers = reestimate
    modelLikelihood = modelLikelihood
    summarizeHypers ms = 
        "  phi  : "++show (dmAlpha $ snd $ M.findMin $ stPhis ms)++"\n"++
        "  theta: "++show (dmAlpha $ snd $ M.findMin $ stThetas ms)++"\n"

main :: IO ()
main = do
    args <- execParser opts
    stopWords <- case stopwords args of
                     Just f  -> S.fromList . T.words <$> TIO.readFile f
                     Nothing -> return S.empty
    printf "Read %d stopwords\n" (S.size stopWords)

    (nodeItems, itemMap) <- termsToItems
                            <$> readNodeItems stopWords (nodesFile args)
    BS.writeFile ("sweeps" </> "node-map") $ runPut $ put itemMap
    let termCounts = V.fromListN (M.size nodeItems)
                     $ map length $ M.elems nodeItems :: Vector Int
    printf "Read %d nodes\n" (M.size nodeItems)
    printf "Mean items per node:  %1.2f\n" (mean $ V.map realToFrac termCounts)
    
    withSystemRandom $ \mwc->do
    let nd = netData nodeItems (nTopics args)
    BS.writeFile ("sweeps" </> "data") $ runPut $ put nd
    mInit <- runRVar (randomInitialize nd) mwc
    let m = model nd mInit
    Sampler.runSampler (samplerOpts args) m (updateUnits nd)
    return ()
    
-- FIXME: Why isn't there already an instance?
instance Serialize T.Text where
     put = put . TE.encodeUtf8
     get = TE.decodeUtf8 <$> get
