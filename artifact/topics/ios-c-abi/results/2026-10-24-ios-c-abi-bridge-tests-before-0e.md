# ブリッジのテスト（UnityIosPluginTests）の記録

- 記録日: 2026-10-24
- 根拠: `README.md` の D-22。段階 0e で `UnityIosPlugin` をワークスペースのビルドと `test_ios.sh` から外す前に、ブリッジのテストを一度流して結果を残す（`test_ios.sh` の基準には入れない）
- 環境: シミュレーター（iPhone 17、iOS 26.2）、Xcode 26.3（17C529）。コミット 2e381fb3 のコード
- 流し方: `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin`（`-derivedDataPath` と `-resultBundlePath` は scratchpad。`.xcresult` はリポジトリに入れていない）
- 結果: **83 件すべてが成功**（失敗 0、skip 0、Expected Failure 0）

段階 1b で、移すロジックに当たるブリッジのテストを `IosLibrary` のテストに書き直すときの参照にする。ブリッジのソースは段階 3 まで残る。

合計 83 件: Passed 83

| スイート | テスト | 結果 |
|---|---|---|
| UnityIosClipboardManagerCallbackContractTests | `handlerFromABackgroundThreadIsDeliveredOnceOnTheMainThread()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `malformedRequestStillDeliversExactlyOnce()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `malformedOperationRequestFromBackgroundIsDeliveredOnTheMainThread()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `rejectedAppendOptionsFromBackgroundAreDeliveredOnTheMainThread()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `malformedJSONCallbackRequestFromBackgroundIsDeliveredOnTheMainThread()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `malformedObserveRequestFromBackgroundDeliversStartHandlerOnTheMainThread()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `nilHandlerIsAccepted()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `startObservingDeliversStartHandlerOnceThenStopObservingDoes()` | Passed |
| UnityIosClipboardManagerCallbackContractTests | `malformedObserveRequestDeliversStartHandlerAndNeverTheChangeHandler()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentNoSoundDefaultsToDefault()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentSoundCustomName()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerInvalidJsonReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentWithRequiredFields()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryMissingIdentifierReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentWithAllOptionalFields()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerLocationMissingRequiredFieldReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryWithIdentifier()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryOptions()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryActionMissingRequiredFieldIsSkipped()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerCalendarPartialComponents()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentMissingIdReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryWithActions()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentMissingTitleReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentAttachmentMissingFileURLIsSkipped()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryNoOptionsIsEmpty()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryInvalidJsonReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentNoAttachmentsIsEmpty()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentInterruptionLevelPassive()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentInterruptionLevelCritical()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerNilReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentInvalidJsonReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerCalendar()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentWithAttachments()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentAttachmentMissingIdentifierIsSkipped()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentSoundDefault()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentNoInterruptionLevelIsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerLocation()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerTimeIntervalDefaultsRepeatsToFalse()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentInterruptionLevelTimeSensitive()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryActionAllOptions()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentInterruptionLevelActive()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerUnknownTypeReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentSoundDefaultCritical()` | Passed |
| UnityIosNotificationJsonParserTests | `parseContentUnknownInterruptionLevelFallsBackToActive()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerLocationDefaultsEntryExitFlags()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerTimeIntervalMissingIntervalReturnsNil()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryWithTextInputActions()` | Passed |
| UnityIosNotificationJsonParserTests | `parseTriggerTimeInterval()` | Passed |
| UnityIosNotificationJsonParserTests | `parseCategoryTextInputActionMissingRequiredFieldIsSkipped()` | Passed |
| UnityIosShareJsonParserTests | `parseContentParsesAllFourTypes()` | Passed |
| UnityIosShareJsonParserTests | `parseContentInvalidJsonReturnsNil()` | Passed |
| UnityIosShareJsonParserTests | `parseContentIgnoresUnknownTypeAndMissingValue()` | Passed |
| UnityIosShareJsonParserTests | `parseContentWithOptionalFields()` | Passed |
| UnityIosShareJsonParserTests | `parseContentKeepsUnvalidatedUrlString()` | Passed |
| UnityIosShareJsonParserTests | `parseContentMissingItemsReturnsNil()` | Passed |
| UnityIosShareJsonParserTests | `parseContentReturnsEmptyItemsWhenAllIgnored()` | Passed |
| UnityIosPluginTests | `example()` | Passed |
| UnityIosShareManagerTests | `shareWithInvalidJsonInvokesHandlerOnMainThreadWithError()` | Passed |
| UnityIosClipboardJsonParserTests | `unknownPatternIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `scopeRoundTripsForAllThreeKinds()` | Passed |
| UnityIosClipboardJsonParserTests | `presentButNonBoolLocalOnlyIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `unknownScopeKindIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `calendarEventDatesSerializeAsRoundTrippableISO8601()` | Passed |
| UnityIosClipboardJsonParserTests | `successEnvelopeShape()` | Passed |
| UnityIosClipboardJsonParserTests | `unknownContentKindIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `appendRequestWithOptionsKeyIsDetected()` | Passed |
| UnityIosClipboardJsonParserTests | `loadedItemSerializesAllFourKinds()` | Passed |
| UnityIosClipboardJsonParserTests | `loadRequestFileKindRequiresUTType()` | Passed |
| UnityIosClipboardJsonParserTests | `patternsRoundTrip()` | Passed |
| UnityIosClipboardJsonParserTests | `invalidBase64IsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `errorEnvelopeShape()` | Passed |
| UnityIosClipboardJsonParserTests | `malformedExpirationDateIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `plainTextContentRoundTrips()` | Passed |
| UnityIosClipboardJsonParserTests | `emptyPatternsArrayParsesToEmptySet()` | Passed |
| UnityIosClipboardJsonParserTests | `scopeDefaultsToGeneralWhenOmitted()` | Passed |
| UnityIosClipboardJsonParserTests | `absentOptionsYieldsDefault()` | Passed |
| UnityIosClipboardJsonParserTests | `nullRequestJsonIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `malformedJsonIsRejected()` | Passed |
| UnityIosClipboardJsonParserTests | `imageDataContentDecodesBase64()` | Passed |
| UnityIosClipboardJsonParserTests | `malformedOptionsIsRejectedRatherThanTreatedAsAbsent(_:)` | Passed |
| UnityIosClipboardJsonParserTests | `malformedScopeIsRejectedRatherThanTreatedAsGeneral(_:)` | Passed |
| UnityIosClipboardJsonParserTests | `omittedLocalOnlyFallsBackToTheDocumentedDefault(_:)` | Passed |
| UnityIosClipboardJsonParserTests | `expirationDateAcceptsISO8601WithAndWithoutFractionalSeconds(_:)` | Passed |
