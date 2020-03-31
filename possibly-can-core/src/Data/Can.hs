{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}
module Data.Can
( -- * Datatypes
  Can(..)
  -- * Combinators
  -- ** Eliminators
, can
, fromCan
, joinCan
, joinWith
  -- ** Partitioning
, partition
, partitionAll
, partitionEithers
  -- ** Distributivity
, distributeCan
, codistributeCan
  -- ** Associativity
, reassocLR
, reassocRL
  -- ** Symmetry
, swapCan
) where


import Data.Bifunctor
import Data.Bifoldable
import Data.Bitraversable
import Data.Data
import qualified Data.Either as E
import Data.Hashable
import Data.List.NonEmpty (NonEmpty(..))
import Data.Typeable

import GHC.Generics


-- | The 'Can' data type represents values with two non-exclusive
-- possibilities, as well as an empty case
--
--
data Can a b = Non | One a | Eno b | Two a b
  deriving
    ( Eq, Ord, Read, Show
    , Generic, Generic1
    , Typeable, Data
    )

-- -------------------------------------------------------------------- --
-- Eliminators

-- | Case eliminator for the 'Can' datatype
--
can
    :: c
      -- ^ default value to supply for the 'Non' case
    -> (a -> c)
      -- ^ eliminator for the 'One' case
    -> (b -> c)
      -- ^ eliminator for the 'Eno' case
    -> (a -> b -> c)
      -- ^ eliminator for the 'Two' case
    -> Can a b
    -> c
can c _ _ _ Non = c
can _ f _ _ (One a) = f a
can _ _ g _ (Eno b) = g b
can _ _ _ h (Two a b) = h a b

-- | Given two default values, create a 'Maybe' value containing
-- either nothing, or just a tuple.
--
fromCan :: a -> b -> Can a b -> Maybe (a,b)
fromCan a b = can Nothing (Just . (,b)) (Just . (a,)) (\c d -> Just (c,d))

-- | Merge the values of a 'Can', using some default value as a local unit.
--
joinCan :: a -> (a -> a -> a) -> Can a a -> a
joinCan a k = can a (k a) (k a) k

-- | Merge the values of a 'Can', using some default value as a local unit,
-- providing a conversion to 'bimap' with before merging.
--
joinWith
    :: c
    -> (a -> c)
    -> (b -> c)
    -> (c -> c -> c)
    -> Can a b
    -> c
joinWith c f g k = joinCan c k . bimap f g

-- -------------------------------------------------------------------- --
-- Partitioning

-- | Partition a list of 'Can' values into a triple of lists of
-- all of their constituent parts
--
partitionAll :: [Can a b] -> ([a], [b], [(a,b)])
partitionAll = flip foldr mempty $ \a ~(as, bs, cs) -> case a of
    Non -> (as, bs, cs)
    One a -> (a:as, bs, cs)
    Eno b -> (as, b:bs, cs)
    Two a b -> (as, bs, (a,b):cs)

-- | Partition a list of 'Can' values into a tuple of lists of
-- their parts.
--
partition :: [Can a b] -> ([a], [b])
partition = flip foldr mempty $ \a ~(as, bs) -> case a of
    Non -> (as, bs)
    One a -> (a:as, bs)
    Eno b -> (as, b:bs)
    Two a b -> (a:as, b:bs)

-- | Partition a list of 'Either' values, separating them into
-- a 'Can' value of lists of left and right values, or 'Non' in the
-- case of an empty list.
--
partitionEithers :: [Either a b] -> Can [a] [b]
partitionEithers = go . E.partitionEithers
  where
    go ([], []) = Non
    go (ls, []) = One ls
    go ([], rs) = Eno rs
    go (ls, rs) = Two ls rs

-- -------------------------------------------------------------------- --
-- Distributivity

-- | Distribute a 'Can' value over a product.
--
distributeCan :: Can (a,b) c -> (Can a c, Can b c)
distributeCan = \case
    Non -> (Non, Non)
    One (a,b) -> (One a, One b)
    Eno c -> (Eno c, Eno c)
    Two (a,b) c -> (Two a c, Two b c)

-- | Codistribute a coproduct over a 'Can' value.
--
codistributeCan :: Either (Can a c) (Can b c) -> Can (Either a b) c
codistributeCan = \case
    Left ac -> case ac of
      Non -> Non
      One a -> One (Left a)
      Eno c -> Eno c
      Two a c -> Two (Left a) c
    Right bc -> case bc of
      Non -> Non
      One b -> One (Right b)
      Eno c -> Eno c
      Two b c -> Two (Right b) c

-- -------------------------------------------------------------------- --
-- Associativity

reassocLR :: Can (Can a b) c -> Can a (Can b c)
reassocLR = \case
    Non -> Non
    One can -> case can of
      Non -> Eno Non
      One a -> One a
      Eno b -> Eno (One b)
      Two a b -> Two a (One b)
    Eno c -> Eno (Eno c)
    Two can c -> case can of
      Non -> Eno (Eno c)
      One a -> Two a (Eno c)
      Eno b -> Eno (Two b c)
      Two a b -> Two a (Two b c)

reassocRL :: Can a (Can b c) -> Can (Can a b) c
reassocRL = \case
    Non -> Non
    One a -> One (One a)
    Eno can -> case can of
      Non -> One Non
      One b -> One (Eno b)
      Eno c -> Eno c
      Two b c -> Two (Eno b) c
    Two a can -> case can of
      Non -> One (One a)
      One b -> One (Two a b)
      Eno c -> Two (One a) c
      Two b c -> Two (Two a b) c

-- -------------------------------------------------------------------- --
-- Symmetry

swapCan :: Can a b -> Can b a
swapCan = \case
    Non -> Non
    One a -> Eno a
    Eno b -> One b
    Two a b -> Two b a

-- -------------------------------------------------------------------- --
-- Std instances


instance (Hashable a, Hashable b) => Hashable (Can a b)

instance Semigroup a => Applicative (Can a) where
  pure = Eno

  _ <*> Non = Non
  Non <*> _ = Non
  One a <*> _ = One a
  Eno _ <*> One b = One b
  Eno f <*> Eno a = Eno (f a)
  Eno f <*> Two a b = Two a (f b)
  Two a f <*> One b = One (a <> b)
  Two a f <*> Eno b = Two a (f b)
  Two a f <*> Two b c = Two (a <> b) (f c)

instance Semigroup a => Monad (Can a) where
  return = pure

  Non >>= _ = Non
  One a >>= k = One a
  Eno b >>= k = k b
  Two a b >>= k = case k b of
    Non -> Non
    One c -> One (a <> c)
    Eno c -> Eno c
    Two c d -> Two (a <> c) d

  (>>) = (*>)

instance (Semigroup a, Semigroup b) => Semigroup (Can a b) where
  Non <> b = b
  b <> Non = b
  One a <> One b = One (a <> b)
  One a <> Eno b = Two a b
  One a <> Two b c = Two (a <> b) c
  Eno a <> Eno b = Eno (a <> b)
  Eno b <> One a = Two a b
  Eno b <> Two a c = Two a (b <> c)
  Two a b <> Two c d = Two (a <> c) (b <> d)
  Two a b <> One c = Two (a <> c) b
  Two a b <> Eno c = Two a (b <> c)


instance (Semigroup a, Semigroup b) => Monoid (Can a b) where
  mempty = Non
  mappend = (<>)

instance Functor (Can a) where
  fmap _ Non = Non
  fmap _ (One a) = One a
  fmap f (Eno b) = Eno (f b)
  fmap f (Two a b) = Two a (f b)

instance Foldable (Can a) where
  foldMap k (Eno b) = k b
  foldMap k (Two a b) = k b
  foldMap _ _ = mempty

instance Traversable (Can a) where
  traverse k = \case
    Non -> pure Non
    One a -> pure (One a)
    Eno b -> Eno <$> k b
    Two a b -> Two a <$> k b

-- -------------------------------------------------------------------- --
-- Bifunctors

instance Bifunctor Can where
  bimap f g = \case
    Non -> Non
    One a -> One (f a)
    Eno b -> Eno (g b)
    Two a b -> Two (f a) (g b)

instance Bifoldable Can where
  bifoldMap f g = \case
    Non -> mempty
    One a -> f a
    Eno b -> g b
    Two a b -> f a <> g b

instance Bitraversable Can where
  bitraverse f g = \case
    Non -> pure Non
    One a -> One <$> f a
    Eno b -> Eno <$> g b
    Two a b -> Two <$> f a <*> g b
