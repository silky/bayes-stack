{-# LANGUAGE GeneralizedNewtypeDeriving, CPP #-}

module BayesStack.UniqueKey ( getUniqueKey
                            , getValueMap, getKeyMap
                            , mapTraversable
                            , UniqueKey, UniqueKeyT
                            , runUniqueKey, runUniqueKeyT
                            , runUniqueKey', runUniqueKeyT'
                            ) where

import Prelude hiding (mapM)
import Control.Applicative (Applicative, (<$>))
import Data.Traversable (Traversable, mapM)
import Data.Tuple
import Data.Functor.Identity

import Control.Monad.Trans
import Control.Monad.State.Strict hiding (mapM)

#if __GLASGOW_HASKELL__ >= 706
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
#else
import Data.Map (Map)
import qualified Data.Map as M
#endif

-- | 'UniqueKey val key' is a monad for a calculation of a mapping unique keys
-- 'key' onto values 'val'
type UniqueKey val key = UniqueKeyT val key Identity
newtype UniqueKeyT val key m a = UniqueKeyT (StateT ([key], Map val key) m a)
                              deriving (Monad, Applicative, Functor, MonadTrans)

-- | Get map of unique keys to values
getKeyMap :: (Monad m, Applicative m, Ord key, Ord val) => UniqueKeyT val key m (Map key val)
getKeyMap = M.fromList . map swap . M.toList <$> getValueMap

-- | Get map of values to unique keys
getValueMap :: (Monad m, Applicative m, Ord key, Ord val) => UniqueKeyT val key m (Map val key)
getValueMap = snd <$> UniqueKeyT get

popUniqueKey :: Monad m => UniqueKeyT val key m key
popUniqueKey = do
    (keys, a) <- UniqueKeyT get
    case keys of
        key:rest -> UniqueKeyT (put $! (rest, a)) >> return key
        []      -> error "Ran out of unique keys"

-- | Find the unique key for value 'val' or 'Nothing' if the value is unknown
findUniqueKey :: (Monad m, Applicative m, Ord key, Ord val) => val -> UniqueKeyT val key m (Maybe key)
findUniqueKey value = M.lookup value <$> getValueMap

getUniqueKey :: (Monad m, Applicative m, Ord key, Ord val) => val -> UniqueKeyT val key m key
getUniqueKey x = do
    key <- findUniqueKey x
    case key of
        Just k  -> return k
        Nothing -> do k <- popUniqueKey
                      UniqueKeyT $ modify $ \(keys, keyMap)->(keys, M.insert x k keyMap)
                      return k

runUniqueKey :: (Ord key) => [key] -> UniqueKey val key a -> a
runUniqueKey keys = runIdentity . runUniqueKeyT keys

runUniqueKeyT :: (Monad m, Ord key) => [key] -> UniqueKeyT val key m a -> m a
runUniqueKeyT keys (UniqueKeyT a) = evalStateT a (keys, M.empty)

-- | Run a `UniqueKeyT`, returning the result and the associated key map
runUniqueKeyT' :: (Monad m, Applicative m, Ord key, Ord val) => [key] -> UniqueKeyT val key m a -> m (a, Map key val)
runUniqueKeyT' keys action =
    runUniqueKeyT keys $ do result <- action
                            keyMap <- getKeyMap
                            return (result, keyMap)

-- | Run a `UniqueKey`, returning the result and the associated key map
runUniqueKey' :: (Ord key, Ord val) => [key] -> UniqueKey val key a -> (a, Map key val)
runUniqueKey' keys action =
    runUniqueKey keys $ do result <- action
                           keyMap <- getKeyMap
                           return (result, keyMap)

mapTraversable :: (Traversable t, Ord key, Ord val) => [key] -> t val -> (t key, Map key val)
mapTraversable keys xs = runUniqueKey' keys $ mapM getUniqueKey xs
