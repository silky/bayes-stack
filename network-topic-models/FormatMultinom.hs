{-# LANGUAGE OverloadedStrings #-}

module FormatMultinom ( formatMultinom
                      , formatMultinoms
                      ) where
                      
import           Data.Foldable
import           Data.Monoid

import qualified Data.Text.Lazy.IO as TL
import qualified Data.Text.Lazy.Builder as TB
import           Data.Text.Lazy.Builder.Int
import           Data.Text.Lazy.Builder.RealFloat

import qualified Data.Map as M

import           BayesStack.DirMulti

formatMultinom :: (Ord a, Enum a) => (a -> TB.Builder) -> Int -> Multinom a -> TB.Builder
formatMultinom show n = foldMap formatElem . take n . toList . decProbabilities
    where formatElem (p,x) = 
               "\t" <> show x <> "\t" <> formatRealFloat Exponent (Just 3) p <> "\n"

formatMultinoms :: (Ord k, Ord a, Enum a)
                => (k -> TB.Builder) -> (a -> TB.Builder) -> Int
                -> M.Map k (Multinom a) -> TB.Builder
formatMultinoms showKey showElem n = foldMap go . M.assocs 
    where go (k,v) = showKey k <> "\n"
                   <> formatMultinom showElem n v <> "\n"
