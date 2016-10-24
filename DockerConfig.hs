{-# LANGUAGE BangPatterns       #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
{-# LANGUAGE TemplateHaskell    #-}

module DockerConfig (
  updateDockerConfig
) where


import           App
import           Control.Bool
import           Control.Lens
import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Logger
import           Data.Aeson as A
import           Data.Aeson.Lens
import qualified Data.ByteString.Lazy as LB
import           Data.Maybe
import           Data.Monoid
import qualified Data.Text as T
import           Network.AWS.Data.Text
import           Network.AWS.ECR
import           System.Directory
import           System.FilePath


updateDockerConfig :: [AuthorizationData]
                   -> App ()
updateDockerConfig [] = return ()
updateDockerConfig ads = do

  createConfFileIfDoesntExist

  cfName <- dockerConfFileName
  !conf <- liftIO $ LB.readFile cfName >>= return . decode >>= return . (fromMaybe (object []))

  let validAuths = catMaybes $ fmap authSection ads
      atKey k = _Object . at k
      appendAuth (pep,dauth) c = c & atKey "auths" . non (Object mempty) . atKey pep . non (Object mempty) .~ dauth
      newConf = foldr appendAuth conf validAuths

  $(logDebug) $ T.pack $ "Valid docker auth data: " <> (show validAuths)
  $(logDebug) $ T.pack $ "Updating docker conf to: " <> (show newConf)

  liftIO $ LB.writeFile cfName (encode newConf)


authSection :: AuthorizationData
            -> Maybe (Text, Value)
authSection ad = do
  proxyEp <- ad ^. adProxyEndpoint
  authTok <- ad ^. adAuthorizationToken
  return $ (proxyEp, object [ "email" A..= ("none" :: Text)
                            , "auth"  A..= authTok ])


dockerConfFileName :: App FilePath
dockerConfFileName = liftIO $ do
  h <- getHomeDirectory
  return $ h </> ".docker" </> "config.json"


createConfFileIfDoesntExist :: App ()
createConfFileIfDoesntExist = do
  fn <- dockerConfFileName
  let (dockerDir, _) = splitFileName fn

  created <- liftIO $
    ifThenElseM (doesFileExist fn)
      (return False)
      ( do createDirectoryIfMissing False dockerDir
           writeFile fn "{}"
           return True)

  when created $ $(logInfo) $ T.pack $ "Created default docker config " <> fn