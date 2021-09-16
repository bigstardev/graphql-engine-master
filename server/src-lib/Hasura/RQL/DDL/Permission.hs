module Hasura.RQL.DDL.Permission
    ( CreatePerm
    , runCreatePerm
    , PermDef(..)

    , InsPerm(..)
    , InsPermDef
    , CreateInsPerm
    , buildInsPermInfo

    , SelPerm(..)
    , SelPermDef
    , CreateSelPerm
    , buildSelPermInfo

    , UpdPerm(..)
    , UpdPermDef
    , CreateUpdPerm
    , buildUpdPermInfo

    , DelPerm(..)
    , DelPermDef
    , CreateDelPerm
    , buildDelPermInfo

    , IsPerm(..)

    , DropPerm
    , runDropPerm
    , dropPermissionInMetadata

    , SetPermComment(..)
    , runSetPermComment
    ) where

import           Hasura.Prelude

import qualified Data.HashMap.Strict                as HM
import qualified Data.HashMap.Strict.InsOrd         as OMap
import qualified Data.HashSet                       as HS

import           Control.Lens                       ((.~))
import           Data.Aeson
import           Data.Text.Extended

import qualified Hasura.SQL.AnyBackend              as AB

import           Hasura.EncJSON
import           Hasura.RQL.DDL.Permission.Internal
import           Hasura.RQL.DML.Internal            hiding (askPermInfo)
import           Hasura.RQL.Types
import           Hasura.SQL.Types
import           Hasura.Session



{- Note [Backend only permissions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
As of writing this note, Hasura permission system is meant to be used by the
frontend. After introducing "Actions", the webhook handlers now can make GraphQL
mutations to the server with some backend logic. These mutations shouldn't be
exposed to frontend for any user since they'll bypass the business logic.

For example:-

We've a table named "user" and it has a "email" column. We need to validate the
email address. So we define an action "create_user" and it expects the same inputs
as "insert_user" mutation (generated by Hasura). Now, a role has permission for both
actions and insert operation on the table. If the insert permission is not marked
as "backend_only: true" then it visible to the frontend client along with "creat_user".

Backend only permissions adds an additional privilege to Hasura generated operations.
Those are accessable only if the request is made with `x-hasura-admin-secret`
(if authorization is configured), `x-hasura-use-backend-only-permissions`
(value must be set to "true"), `x-hasura-role` to identify the role and other
required session variables.

backend_only   `x-hasura-admin-secret`   `x-hasura-use-backend-only-permissions`  Result
------------    ---------------------     -------------------------------------   ------
FALSE           ANY                       ANY                                    Mutation is always visible
TRUE            FALSE                     ANY                                    Mutation is always hidden
TRUE            TRUE (OR NOT-SET)         FALSE                                  Mutation is hidden
TRUE            TRUE (OR NOT-SET)         TRUE                                   Mutation is shown
-}

type CreateInsPerm b = CreatePerm b (InsPerm b)

procSetObj
  :: (QErrM m, BackendMetadata b)
  => SourceName
  -> TableName b
  -> FieldInfoMap (FieldInfo b)
  -> Maybe (ColumnValues b Value)
  -> m (PreSetColsPartial b, [Text], [SchemaDependency])
procSetObj source tn fieldInfoMap mObj = do
  (setColTups, deps) <- withPathK "set" $
    fmap unzip $ forM (HM.toList setObj) $ \(pgCol, val) -> do
      ty <- askColumnType fieldInfoMap pgCol $
        "column " <> pgCol <<> " not found in table " <>> tn
      sqlExp <- parseCollectableType (CollectableTypeScalar ty) val
      let dep = mkColDep (getDepReason sqlExp) source tn pgCol
      return ((pgCol, sqlExp), dep)
  return (HM.fromList setColTups, depHeaders, deps)
  where
    setObj = fromMaybe mempty mObj
    depHeaders = getDepHeadersFromVal $ Object $ mapKeys toTxt setObj

    getDepReason = bool DRSessionVariable DROnType . isStaticValue

class (ToJSON a) => IsPerm b a where

  permAccessor
    :: PermAccessor b (PermInfo b a)

  buildPermInfo
    :: (QErrM m, TableCoreInfoRM b m)
    => SourceName
    -> TableName b
    -> FieldInfoMap (FieldInfo b)
    -> PermDef a
    -> m (WithDeps (PermInfo b a))

  getPermAcc1
    :: PermDef a -> PermAccessor b (PermInfo b a)
  getPermAcc1 _ = permAccessor

  getPermAcc2
    :: DropPerm b a -> PermAccessor b (PermInfo b a)
  getPermAcc2 _ = permAccessor

  addPermToMetadata
    :: PermDef a -> TableMetadata b -> TableMetadata b

runCreatePerm
  :: forall m b a
   . (UserInfoM m, CacheRWM m, IsPerm b a, MonadError QErr m, MetadataM m, BackendMetadata b)
  => CreatePerm b a -> m EncJSON
runCreatePerm (WithTable source tn pd) = do
  tableInfo <- askTabInfo source tn
  let permAcc = getPermAcc1 pd
      pt = permAccToType permAcc
      ptText = permTypeToCode pt
      role = _pdRole pd
      metadataObject = MOSourceObjId source
                         $ AB.mkAnyBackend
                         $ SMOTableObj tn
                         $ MTOPerm role pt
  onJust (getPermInfoMaybe role permAcc tableInfo) $ const $ throw400 AlreadyExists $
    ptText <> " permission already defined on table " <> tn <<> " with role " <>> role
  buildSchemaCacheFor metadataObject
    $ MetadataModifier
    $ tableMetadataSetter source tn %~ addPermToMetadata pd
  pure successMsg

runDropPerm
  :: (IsPerm b a, UserInfoM m, CacheRWM m, MonadError QErr m, MetadataM m, BackendMetadata b)
  => DropPerm b a -> m EncJSON
runDropPerm dp@(DropPerm source table role) = do
  tabInfo <- askTabInfo source table
  let permType = permAccToType $ getPermAcc2 dp
  void $ askPermInfo tabInfo role $ getPermAcc2 dp
  withNewInconsistentObjsCheck
    $ buildSchemaCache
    $ MetadataModifier
    $ tableMetadataSetter source table %~ dropPermissionInMetadata role permType
  return successMsg

dropPermissionInMetadata
  :: RoleName -> PermType -> TableMetadata b -> TableMetadata b
dropPermissionInMetadata rn = \case
  PTInsert -> tmInsertPermissions %~ OMap.delete rn
  PTSelect -> tmSelectPermissions %~ OMap.delete rn
  PTDelete -> tmDeletePermissions %~ OMap.delete rn
  PTUpdate -> tmUpdatePermissions %~ OMap.delete rn

buildInsPermInfo
  :: (QErrM m, TableCoreInfoRM b m, BackendMetadata b)
  => SourceName
  -> TableName b
  -> FieldInfoMap (FieldInfo b)
  -> PermDef (InsPerm b)
  -> m (WithDeps (InsPermInfo b))
buildInsPermInfo source tn fieldInfoMap (PermDef _rn (InsPerm checkCond set mCols mBackendOnly) _) =
  withPathK "permission" $ do
    (be, beDeps) <- withPathK "check" $ procBoolExp source tn fieldInfoMap checkCond
    (setColsSQL, setHdrs, setColDeps) <- procSetObj source tn fieldInfoMap set
    void $ withPathK "columns" $ indexedForM insCols $ \col ->
           askColumnType fieldInfoMap col ""
    let fltrHeaders = getDependentHeaders checkCond
        reqHdrs = fltrHeaders `union` setHdrs
        insColDeps = map (mkColDep DRUntyped source tn) insCols
        deps = mkParentDep source tn : beDeps ++ setColDeps ++ insColDeps
        insColsWithoutPresets = insCols \\ HM.keys setColsSQL
    return (InsPermInfo (HS.fromList insColsWithoutPresets) be setColsSQL backendOnly reqHdrs, deps)
  where
    backendOnly = Just True == mBackendOnly
    allCols = map pgiColumn $ getCols fieldInfoMap
    insCols = maybe allCols (convColSpec fieldInfoMap) mCols

type instance PermInfo b (InsPerm b) = InsPermInfo b

instance (BackendMetadata b) => IsPerm b (InsPerm b) where
  permAccessor = PAInsert
  buildPermInfo = buildInsPermInfo

  addPermToMetadata permDef =
    tmInsertPermissions %~ OMap.insert (_pdRole permDef) permDef

buildSelPermInfo
  :: (QErrM m, TableCoreInfoRM b m, BackendMetadata b)
  => SourceName
  -> TableName b
  -> FieldInfoMap (FieldInfo b)
  -> SelPerm b
  -> m (WithDeps (SelPermInfo b))
buildSelPermInfo source tn fieldInfoMap sp = withPathK "permission" $ do
  let pgCols     = convColSpec fieldInfoMap $ spColumns sp

  (boolExp, boolExpDeps) <- withPathK "filter" $
    procBoolExp source tn fieldInfoMap  $ spFilter sp

  -- check if the columns exist
  void $ withPathK "columns" $ indexedForM pgCols $ \pgCol ->
    askColumnType fieldInfoMap pgCol autoInferredErr

  -- validate computed fields
  scalarComputedFields <-
    withPathK "computed_fields" $ indexedForM computedFields $ \fieldName -> do
      computedFieldInfo <- askComputedFieldInfo fieldInfoMap fieldName
      case _cfiReturnType computedFieldInfo of
        CFRScalar _               -> pure fieldName
        CFRSetofTable returnTable -> throw400 NotSupported $
          "select permissions on computed field " <> fieldName
          <<> " are auto-derived from the permissions on its returning table "
          <> returnTable <<> " and cannot be specified manually"

  let deps = mkParentDep source tn : boolExpDeps ++ map (mkColDep DRUntyped source tn) pgCols
             ++ map (mkComputedFieldDep DRUntyped source tn) scalarComputedFields
      depHeaders = getDependentHeaders $ spFilter sp
      mLimit = spLimit sp

  withPathK "limit" $ mapM_ onlyPositiveInt mLimit

  let pgColsWithFilter = HM.fromList $ map (, Nothing) pgCols
      scalarComputedFieldsWithFilter = HS.toMap (HS.fromList scalarComputedFields) $> Nothing

  let selPermInfo =
        SelPermInfo pgColsWithFilter scalarComputedFieldsWithFilter boolExp mLimit allowAgg depHeaders

  return ( selPermInfo, deps )
  where
    allowAgg = spAllowAggregations sp
    computedFields = spComputedFields sp
    autoInferredErr = "permissions for relationships are automatically inferred"

type CreateSelPerm b = CreatePerm b (SelPerm b)

type instance PermInfo b (SelPerm b) = SelPermInfo b

instance (BackendMetadata b) => IsPerm b (SelPerm b) where
  permAccessor = PASelect
  buildPermInfo source tn fieldInfoMap (PermDef _ a _) =
    buildSelPermInfo source tn fieldInfoMap a

  addPermToMetadata permDef =
    tmSelectPermissions %~ OMap.insert (_pdRole permDef) permDef

type CreateUpdPerm b = CreatePerm b (UpdPerm b)

buildUpdPermInfo
  :: (QErrM m, TableCoreInfoRM b m, BackendMetadata b)
  => SourceName
  -> TableName b
  -> FieldInfoMap (FieldInfo b)
  -> UpdPerm b
  -> m (WithDeps (UpdPermInfo b))
buildUpdPermInfo source tn fieldInfoMap (UpdPerm colSpec set fltr check) = do
  (be, beDeps) <- withPathK "filter" $
    procBoolExp source tn fieldInfoMap fltr

  checkExpr <- traverse (withPathK "check" . procBoolExp source tn fieldInfoMap) check

  (setColsSQL, setHeaders, setColDeps) <- procSetObj source tn fieldInfoMap set

  -- check if the columns exist
  void $ withPathK "columns" $ indexedForM updCols $ \updCol ->
       askColumnType fieldInfoMap updCol relInUpdErr

  let updColDeps = map (mkColDep DRUntyped source tn) updCols
      deps = mkParentDep source tn : beDeps ++ maybe [] snd checkExpr ++ updColDeps ++ setColDeps
      depHeaders = getDependentHeaders fltr
      reqHeaders = depHeaders `union` setHeaders
      updColsWithoutPreSets = updCols \\ HM.keys setColsSQL

  return (UpdPermInfo (HS.fromList updColsWithoutPreSets) tn be (fst <$> checkExpr) setColsSQL reqHeaders, deps)

  where
    updCols     = convColSpec fieldInfoMap colSpec
    relInUpdErr = "relationships can't be used in update"

-- TODO see TODO for PermInfo above
type instance PermInfo b (UpdPerm b) = UpdPermInfo b

instance (BackendMetadata b) => IsPerm b (UpdPerm b) where
  permAccessor = PAUpdate
  buildPermInfo source tn fieldInfoMap (PermDef _ a _) =
    buildUpdPermInfo source tn fieldInfoMap a

  addPermToMetadata permDef =
    tmUpdatePermissions %~ OMap.insert (_pdRole permDef) permDef

type CreateDelPerm b = CreatePerm b (DelPerm b)

buildDelPermInfo
  :: (QErrM m, TableCoreInfoRM b m, BackendMetadata b)
  => SourceName
  -> TableName b
  -> FieldInfoMap (FieldInfo b)
  -> DelPerm b
  -> m (WithDeps (DelPermInfo b))
buildDelPermInfo source tn fieldInfoMap (DelPerm fltr) = do
  (be, beDeps) <- withPathK "filter" $
    procBoolExp source tn fieldInfoMap  fltr
  let deps = mkParentDep source tn : beDeps
      depHeaders = getDependentHeaders fltr
  return (DelPermInfo tn be depHeaders, deps)

-- TODO see TODO for PermInfo above
type instance PermInfo b (DelPerm b) = DelPermInfo b

instance (BackendMetadata b) => IsPerm b (DelPerm b) where
  permAccessor = PADelete
  buildPermInfo source tn fieldInfoMap (PermDef _ a _) =
    buildDelPermInfo source tn fieldInfoMap a

  addPermToMetadata permDef =
    tmDeletePermissions %~ OMap.insert (_pdRole permDef) permDef

data SetPermComment b
  = SetPermComment
  { apSource     :: !SourceName
  , apTable      :: !(TableName b)
  , apRole       :: !RoleName
  , apPermission :: !PermType
  , apComment    :: !(Maybe Text)
  } deriving (Generic)
deriving instance (Backend b) => Show (SetPermComment b)
deriving instance (Backend b) => Eq (SetPermComment b)
instance (Backend b) => ToJSON (SetPermComment b) where
  toJSON = genericToJSON hasuraJSON

instance (Backend b) => FromJSON (SetPermComment b) where
  parseJSON = withObject "Object" $ \o ->
    SetPermComment
      <$> o .:? "source" .!= defaultSource
      <*> o .: "table"
      <*> o .: "role"
      <*> o .: "permission"
      <*> o .:? "comment"

runSetPermComment
  :: forall m b
   . (QErrM m, CacheRWM m, MetadataM m, BackendMetadata b)
  => SetPermComment b -> m EncJSON
runSetPermComment (SetPermComment source table roleName permType comment) =  do
  tableInfo <- askTabInfo source table

  -- assert permission exists and return appropriate permission modifier
  permModifier <- case permType of
    PTInsert -> do
      assertPermDefined roleName PAInsert tableInfo
      pure $ tmInsertPermissions.ix roleName.pdComment .~ comment
    PTSelect -> do
      assertPermDefined roleName PASelect tableInfo
      pure $ tmSelectPermissions.ix roleName.pdComment .~ comment
    PTUpdate -> do
      assertPermDefined roleName PAUpdate tableInfo
      pure $ tmUpdatePermissions.ix roleName.pdComment .~ comment
    PTDelete -> do
      assertPermDefined roleName PADelete tableInfo
      pure $ tmDeletePermissions.ix roleName.pdComment .~ comment

  let metadataObject = MOSourceObjId source
                         $ AB.mkAnyBackend
                         $ SMOTableObj table
                         $ MTOPerm roleName permType
  buildSchemaCacheFor metadataObject
    $ MetadataModifier
    $ tableMetadataSetter source table %~ permModifier
  pure successMsg