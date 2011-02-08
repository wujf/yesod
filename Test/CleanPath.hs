{-# LANGUAGE QuasiQuotes, TypeFamilies, TemplateHaskell, MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
module Test.CleanPath (cleanPathTest) where

import Yesod.Core
import Yesod.Content
import Yesod.Dispatch
import Yesod.Handler (Route)

import Test.Framework (defaultMain, testGroup, Test)
import Test.Framework.Providers.HUnit
import Test.HUnit hiding (Test)
import Network.Wai
import Network.Wai.Test

import qualified Data.ByteString.Lazy.Char8 as L8

data Subsite = Subsite
getSubsite = const Subsite
data SubsiteRoute = SubsiteRoute [String]
    deriving (Eq, Show, Read)
type instance Route Subsite = SubsiteRoute
instance RenderRoute SubsiteRoute where
    renderRoute (SubsiteRoute x) = (x, [])

instance YesodDispatch Subsite master where
    yesodDispatch _ _ pieces _ _ = Just $ const $ return $ responseLBS
        status200
        [ ("Content-Type", "SUBSITE")
        ] $ L8.pack $ show pieces

data Y = Y
mkYesod "Y" [$parseRoutes|
/foo FooR GET
/foo/#String FooStringR GET
/bar BarR GET
/subsite SubsiteR Subsite getSubsite
|]

instance Yesod Y where
    approot _ = "http://test"
    cleanPath _ ["bar", ""] = Right ["bar"]
    cleanPath _ ["bar"] = Left ["bar", ""]
    cleanPath _ s =
        if corrected == s
            then Right s
            else Left corrected
      where
        corrected = filter (not . null) s

getFooR = return $ RepPlain "foo"
getFooStringR = return . RepPlain . toContent
getBarR = return $ RepPlain "bar"

cleanPathTest :: Test
cleanPathTest = testGroup "Test.CleanPath"
    [ testCase "remove trailing slash" removeTrailingSlash
    , testCase "noTrailingSlash" noTrailingSlash
    , testCase "add trailing slash" addTrailingSlash
    , testCase "has trailing slash" hasTrailingSlash
    , testCase "/foo/something" fooSomething
    , testCase "subsite dispatch" subsiteDispatch
    ]

runner f = toWaiApp Y >>= runSession f
defaultRequest = Request
    { pathInfo = ""
    , requestHeaders = []
    , queryString = ""
    , requestMethod = "GET"
    }

removeTrailingSlash = runner $ do
    res <- request defaultRequest
                { pathInfo = "/foo/"
                }
    assertStatus 301 res
    assertHeader "Location" "http://test/foo" res

noTrailingSlash = runner $ do
    res <- request defaultRequest
                { pathInfo = "/foo"
                }
    assertStatus 200 res
    assertContentType "text/plain; charset=utf-8" res
    assertBody "foo" res

addTrailingSlash = runner $ do
    res <- request defaultRequest
                { pathInfo = "/bar"
                }
    assertStatus 301 res
    assertHeader "Location" "http://test/bar/" res

hasTrailingSlash = runner $ do
    res <- request defaultRequest
                { pathInfo = "/bar/"
                }
    assertStatus 200 res
    assertContentType "text/plain; charset=utf-8" res
    assertBody "bar" res

fooSomething = runner $ do
    res <- request defaultRequest
                { pathInfo = "/foo/something"
                }
    assertStatus 200 res
    assertContentType "text/plain; charset=utf-8" res
    assertBody "something" res

subsiteDispatch = runner $ do
    res <- request defaultRequest
                { pathInfo = "/subsite/1/2/3/"
                }
    assertStatus 200 res
    assertContentType "SUBSITE" res
    assertBody "[\"1\",\"2\",\"3\",\"\"]" res
