

This module represents part of the bound names environment used in the
type checker. It doesn't cover the stuff that is contained in the
catalog (so it is slightly misnamed), but focuses only on identifiers
introduced by things like tablerefs, sub selects, plpgsql parameters
and variables, etc.

> {-# LANGUAGE DeriveDataTypeable #-}
> module Database.HsSqlPpp.Internals.TypeChecking.Environment
>     (-- * abstract environment value
>      Environment
>      -- * environment create and update functions
>     ,emptyEnvironment
>     ,isEmptyEnv
>     ,envCreateTrefEnvironment
>     ,createJoinTrefEnvironment
>     ,envSelectListEnvironment
>     ,createCorrelatedSubqueryEnvironment
>      -- * environment query functions
>     ,envLookupIdentifier
>     ,envExpandStar
>     ) where

> import Data.Data
> --import Data.Char
> import Data.Maybe
> import Control.Monad
> --import Control.Arrow
> import Data.List
> import Debug.Trace

> import Database.HsSqlPpp.Internals.TypesInternal
> import Database.HsSqlPpp.Internals.TypeChecking.TypeConversion
> import Database.HsSqlPpp.Internals.Catalog.CatalogInternal

---------------------------------

> -- | Represent an environment using an abstracted version of the syntax
> -- which produced the environment. This structure has all the catalog
> -- queries resolved. No attempt is made to combine environment parts from
> -- different sources, they are just stacked together, the logic for
> -- working with combined environments is in the query functions below
> data Environment =
>                  -- | represents an empty environment, makes e.g. joining
>                  -- the environments for a list of trefs in a select list
>                  -- more straightforward
>                    EmptyEnvironment
>                  -- | represents the bindings introduced by a tableref:
>                  -- the name, the public fields, the private fields
>                  | SimpleTref String [(String,Type)] [(String,Type)]
>                  | JoinTref [(String,Type)] -- join ids
>                             Environment Environment
>                  | SelectListEnv [(String,Type)]
>                    -- | correlated subquery environment
>                  | CSQEnv Environment -- outerenv
>                           Environment -- main env
>                    deriving (Data,Typeable,Show,Eq)



---------------------------------------------------

Create/ update functions, these are shortcuts to create environment variables,
the main purpose is to encapsulate looking up information in the
catalog and combining environment values with updates

> emptyEnvironment :: Environment
> emptyEnvironment = EmptyEnvironment

> isEmptyEnv :: Environment -> Bool
> isEmptyEnv EmptyEnvironment = True
> isEmptyEnv _ = False

> envCreateTrefEnvironment :: Catalog -> [NameComponent] -> Either [TypeError] Environment
> envCreateTrefEnvironment cat tbnm = do
>   (nm,pub,prv) <- catLookupTableAndAttrs cat tbnm
>   return $ SimpleTref nm pub prv

> envSelectListEnvironment :: [(String,Type)] -> Either [TypeError] Environment
> envSelectListEnvironment cols = do
>   return $ SelectListEnv cols


> -- | create an environment as two envs joined together
> createJoinTrefEnvironment :: Catalog
>                           -> Environment
>                           -> Environment
>                           -> Maybe [NameComponent] -- join ids: empty if cross join
>                                                    -- nothing for natural join
>                           -> Either [TypeError] Environment
> createJoinTrefEnvironment cat tref0 tref1 jsc = do
>   -- todo: handle natural join case
>   (jids::[String]) <- case jsc of
>             Nothing -> do
>                        j0 <- fmap (map (snd . fst)) $ envExpandStar Nothing tref0
>                        j1 <- fmap (map (snd . fst)) $ envExpandStar Nothing tref1
>                        return $ j0 `intersect` j1
>             Just x -> return $ map ncStr x

>  --         maybe (error "natural join ids") (map (nnm . (:[]))) jsc

>   jts <- forM jids $ \i -> do
>            (_,t0) <- envLookupIdentifier [QNmc i] tref0
>            (_,t1) <- envLookupIdentifier [QNmc i] tref1
>            fmap (i,) $ resolveResultSetType cat [t0,t1]
>   -- todo: check type compatibility
>   return $ JoinTref jts tref0 tref1

> createCorrelatedSubqueryEnvironment :: Environment -> Environment -> Environment
> createCorrelatedSubqueryEnvironment cenv env =
>   CSQEnv cenv env



-------------------------------------------------------


The main hard work is done in the query functions: so the idea is that
the update functions create environment values which contain the
context free contributions of each part of the ast to the current
environment, and these query functions do all the work of resolving
implicit correlation names, ambigous identifiers, etc.

for each environment type, provide two functions which do identifier
lookup and star expansion

> listBindingsTypes :: Environment -> ((Maybe String,String) -> [((String,String),Type)]
>                                     ,Maybe String -> [((String,String),Type)] -- star expand
>                                     )
> listBindingsTypes EmptyEnvironment = (const [],const [])

> listBindingsTypes (SimpleTref nm pus pvs) =
>   (\(q,n) -> let m (n',t) = (q `elem` [Nothing,Just nm])
>                             && n == n'
>              in addQual nm $ filter m $ pus ++ pvs
>   ,\q -> case () of
>            _ | q `elem` [Nothing, Just nm] -> addQual nm pus
>              | otherwise -> [])

> listBindingsTypes (JoinTref jids env0 env1) =
>   (idens,starexp)
>   where

>     idens k = let i0 = is0 k
>                   i1 = is1 k
>               in if (not (null i0) && (snd k) `elem` jnames)
>                  then i0
>                  else i0 ++ i1

>     useResolvedType tr@((q,n),_) = case lookup n jids of
>                                    Just t' -> ((q,n),t')
>                                    Nothing -> tr
>     jnames = map fst jids
>     isJ ((_,n),_) = n `elem` jnames

todo: use useResolvedType

unqualified star:
reorder the ids so that the join columns are first

>     starexp Nothing = let (aj,anj) = partition isJ (st0 Nothing)
>                           bnj = filter (not . isJ) (st1 Nothing)
>                       in aj ++ anj ++ bnj
>     starexp q@(Just _) =
>       let s0 = st0 q
>           s1 = st1 q
>       in case (s0,s1) of
>            -- if we only get ids from one side, then don't
>            -- reorder them (is this right?)
>            (_:_,[]) -> s0
>            ([], _:_) -> s1
>            -- have ids coming from both sides
>            -- no idea how this is supposed to work
>            _ -> let (aj,anj) = partition isJ s0
>                     bnj = filter (not . isJ) s1
>                 in aj ++ anj ++ bnj
>     (is0,st0) = listBindingsTypes env0
>     (is1,st1) = listBindingsTypes env1

selectlistenv: not quite right, but should always have an alias so the
empty qualifier never gets very far

> listBindingsTypes (SelectListEnv is) =
>   (\(_,n) -> addQual "" $ filter ((==n).fst) is
>   ,const $ addQual "" is)

csq just uses standard shadowing for iden lookup
for star expand, the outer env is ignored

> listBindingsTypes (CSQEnv outerenv env) =
>   (\k -> case (fst (listBindingsTypes env) k
>               ,fst (listBindingsTypes outerenv) k) of
>            (x,_) | not (null x) -> x
>            (_, x) | not (null x)  -> x
>            _ -> []
>   ,snd $ listBindingsTypes env)


> addQual :: String -> [(String,Type)] -> [((String,String),Type)]
> addQual q = map (\(n,t) -> ((q,n),t))


-------------------------------------------------------

use listBindingsTypes to implement expandstar and lookupid

> envExpandStar :: Maybe NameComponent -> Environment -> Either [TypeError] [((String,String),Type)]

> envExpandStar nmc env = {-let r =-} envExpandStar2 nmc env
>                         {-in trace ("env expand star: " ++ show nmc ++ " " ++ show r)
>                            r-}

> envExpandStar2 :: Maybe NameComponent -> Environment -> Either [TypeError] [((String,String),Type)]
> envExpandStar2 nmc env =
>   let st = (snd $ listBindingsTypes env) $ fmap ncStr nmc
>   in if null st
>      then case nmc of
>             Just x -> Left [UnrecognisedCorrelationName $ ncStr x]
>             Nothing -> Left [BadStarExpand]
>      else Right st


> envLookupIdentifier :: [NameComponent] -> Environment
>                      -> Either [TypeError] ((String,String), Type)
> envLookupIdentifier nmc env = do
>   k <- case nmc of
>              [a,b] -> Right (Just $ ncStr a, ncStr b)
>              [b] -> Right (Nothing, ncStr b)
>              _ -> Left [InternalError "too many nmc components in envlookupiden"]
>   case (fst $ listBindingsTypes env) k of
>     [] -> Left [UnrecognisedIdentifier $ ncStr $ last nmc]
>     [x] -> Right x
>     _ -> Left [AmbiguousIdentifier $ ncStr $ last nmc]
