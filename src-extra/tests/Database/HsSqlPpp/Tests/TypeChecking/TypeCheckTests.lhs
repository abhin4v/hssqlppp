

> module Database.HsSqlPpp.Tests.TypeChecking.TypeCheckTests
>     (typeCheckTests
>     ,typeCheckTestData
>     ,Item(..)) where

> import Test.Framework


> import Database.HsSqlPpp.Tests.TypeChecking.Utils
> import Database.HsSqlPpp.Tests.TypeChecking.ScalarExprs

> typeCheckTestData :: Item
> typeCheckTestData =
>   Group "typeCheckTests"
>     [scalarExprs]

> typeCheckTests :: Test.Framework.Test
> typeCheckTests =
>   itemToTft typeCheckTestData