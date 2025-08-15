//
//  UnityMacDialogManagerBridge.m
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
#import "UnityMacDialogManagerBridge.h"

static NSString *const TAG = @"UnityMacDialogManagerBridge";

void showDialog(const char* title,
                const char* message,
                const char* buttonsJson,
                const char* optionsJson,
                DialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showDialog called with title: %s, message: %s, buttonsJson: %s, optionsJson: %s, callback: %p", title, message, buttonsJson, optionsJson, callback]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    NSString* nsButtonsJson = [NSString stringWithUTF8String:buttonsJson];
    NSString* nsOptionsJson = [NSString stringWithUTF8String:optionsJson];
    
    [[UnityMacDialogManager shared] showDialogWithTitle:nsTitle
                                                message:nsMessage
                                            buttonsJson:nsButtonsJson
                                            optionsJson:nsOptionsJson
                                             completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSString* buttonTitle = result[@"buttonTitle"];
            NSInteger buttonIndex = [result[@"buttonIndex"] integerValue];
            BOOL suppressionButtonState = [result[@"suppressionButtonState"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showDialog buttonTitle: %@, buttonIndex: %d, suppressionButtonState: %d", buttonTitle, (int)buttonIndex, (int)suppressionButtonState]];
            [Log d:TAG :@"showDialog completed successfully"];
            callback(buttonTitle.UTF8String, (int)buttonIndex, suppressionButtonState, YES, NULL);
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NO, NO, errorMessage.UTF8String);
        }
    }];
}

void showFileDialog(const char* title,
                    const char* message,
                    const char** allowedContentTypes,
                    int contentTypesCount,
                    const char* directoryPath,
                    FileDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showFileDialog called with title: %s, message: %s", title, message]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    
    // Convert allowedContentTypes array to NSArray
    NSMutableArray<NSString*>* nsAllowedContentTypes = [NSMutableArray array];
    for (int i = 0; i < contentTypesCount; i++) {
        NSString* contentType = [NSString stringWithUTF8String:allowedContentTypes[i]];
        [nsAllowedContentTypes addObject:contentType];
    }
    
    // Convert directoryPath to URL
    NSURL* directoryURL = nil;
    if (directoryPath != NULL && strlen(directoryPath) > 0) {
        directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directoryPath]];
    }
    
    [[UnityMacDialogManager shared] showFileDialogWithTitle:nsTitle
                                                    message:nsMessage
                                        allowedContentTypes:nsAllowedContentTypes
                                               directoryURL:directoryURL
                                                 completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSArray<NSString*>* filePaths = result[@"filePaths"];
            NSNumber* fileCount = result[@"fileCount"];
            NSString* directoryURL = result[@"directoryURL"];
            BOOL isCancelled = [result[@"isCancelled"] boolValue];
            BOOL isSuccess = [result[@"isSuccess"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showFileDialog filePaths: %@, fileCount: %@, directoryURL: %@, isCancelled: %d, isSuccess: %d", filePaths, fileCount, directoryURL, (int)isCancelled, (int)isSuccess]];
            
            // Convert NSArray to C array
            const char** cFilePaths = (const char**)malloc(filePaths.count * sizeof(char*));
            for (NSUInteger i = 0; i < filePaths.count; i++) {
                cFilePaths[i] = [filePaths[i] UTF8String];
            }
            
            if (isCancelled) {
                [Log d:TAG :@"showFileDialog was cancelled"];
                callback(NULL, -1, NULL, isCancelled, isSuccess, NULL);
            } else {
                [Log d:TAG :@"showFileDialog completed successfully"];
                callback(cFilePaths, (int)filePaths.count, directoryURL.UTF8String, isCancelled, isSuccess, NULL);
            }
            free(cFilePaths);
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showFileDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NULL, NO, NO, errorMessage.UTF8String);
        }
    }];
}

void showMultiFileDialog(const char* title,
                         const char* message,
                         const char** allowedContentTypes,
                         int contentTypesCount,
                         const char* directoryPath,
                         MultiFileDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showMultiFileDialog called with title: %s, message: %s", title, message]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    
    // Convert allowedContentTypes array to NSArray
    NSMutableArray<NSString*>* nsAllowedContentTypes = [NSMutableArray array];
    for (int i = 0; i < contentTypesCount; i++) {
        NSString* contentType = [NSString stringWithUTF8String:allowedContentTypes[i]];
        [nsAllowedContentTypes addObject:contentType];
    }
    
    // Convert directoryPath to URL
    NSURL* directoryURL = nil;
    if (directoryPath != NULL && strlen(directoryPath) > 0) {
        directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directoryPath]];
    }
    
    [[UnityMacDialogManager shared] showMultiFileDialogWithTitle:nsTitle
                                                         message:nsMessage
                                             allowedContentTypes:nsAllowedContentTypes
                                                    directoryURL:directoryURL
                                                      completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSArray<NSString*>* filePaths = result[@"filePaths"];
            NSNumber* fileCount = result[@"fileCount"];
            NSString* directoryURL = result[@"directoryURL"];
            BOOL isCancelled = [result[@"isCancelled"] boolValue];
            BOOL isSuccess = [result[@"isSuccess"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showMultiFileDialog filePaths: %@, fileCount: %@, directoryURL: %@, isCancelled: %d, isSuccess: %d", filePaths, fileCount, directoryURL, (int)isCancelled, (int)isSuccess]];
            
            // Convert NSArray to C array
            const char** cFilePaths = (const char**)malloc(filePaths.count * sizeof(char*));
            for (NSUInteger i = 0; i < filePaths.count; i++) {
                cFilePaths[i] = [filePaths[i] UTF8String];
            }
            
            if (isCancelled) {
                [Log d:TAG :@"showMultiFileDialog was cancelled"];
                callback(NULL, -1, NULL, isCancelled, isSuccess, NULL);
            } else {
                [Log d:TAG :@"showMultiFileDialog completed successfully"];
                callback(cFilePaths, (int)filePaths.count, directoryURL.UTF8String, isCancelled, isSuccess, NULL);
            }
            free(cFilePaths);
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showMultiFileDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NULL, NO, NO, errorMessage.UTF8String);
        }
    }];
}

void showFolderDialog(const char* title,
                      const char* message,
                      const char* directoryPath,
                      FolderDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showFolderDialog called with title: %s, message: %s", title, message]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    
    // Convert directoryPath to URL
    NSURL* directoryURL = nil;
    if (directoryPath != NULL && strlen(directoryPath) > 0) {
        directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directoryPath]];
    }
    
    [[UnityMacDialogManager shared] showFolderDialogWithTitle:nsTitle
                                                      message:nsMessage
                                                 directoryURL:directoryURL
                                                   completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSArray<NSString*>* filePaths = result[@"filePaths"];
            NSNumber* fileCount = result[@"fileCount"];
            NSString* directoryURL = result[@"directoryURL"];
            BOOL isCancelled = [result[@"isCancelled"] boolValue];
            BOOL isSuccess = [result[@"isSuccess"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showFolderDialog filePaths: %@, fileCount: %@, directoryURL: %@, isCancelled: %d, isSuccess: %d", filePaths, fileCount, directoryURL, (int)isCancelled, (int)isSuccess]];
            
            // Convert NSArray to C array
            const char** cFilePaths = (const char**)malloc(filePaths.count * sizeof(char*));
            for (NSUInteger i = 0; i < filePaths.count; i++) {
                cFilePaths[i] = [filePaths[i] UTF8String];
            }
            
            if (isCancelled) {
                [Log d:TAG :@"showFolderDialog was cancelled"];
                callback(NULL, -1, NULL, isCancelled, isSuccess, NULL);
            } else {
                [Log d:TAG :@"showFolderDialog completed successfully"];
                callback(cFilePaths, (int)filePaths.count, directoryURL.UTF8String, isCancelled, isSuccess, NULL);
            }
            free(cFilePaths);
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showFolderDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NULL, NO, NO, errorMessage.UTF8String);
        }
    }];
}

void showMultiFolderDialog(const char* title,
                           const char* message,
                           const char* directoryPath,
                           MultiFolderDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showMultiFolderDialog called with title: %s, message: %s", title, message]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    
    // Convert directoryPath to URL
    NSURL* directoryURL = nil;
    if (directoryPath != NULL && strlen(directoryPath) > 0) {
        directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directoryPath]];
    }
    
    [[UnityMacDialogManager shared] showMultiFolderDialogWithTitle:nsTitle
                                                           message:nsMessage
                                                      directoryURL:directoryURL
                                                        completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSArray<NSString*>* filePaths = result[@"filePaths"];
            NSNumber* fileCount = result[@"fileCount"];
            NSString* directoryURL = result[@"directoryURL"];
            BOOL isCancelled = [result[@"isCancelled"] boolValue];
            BOOL isSuccess = [result[@"isSuccess"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showMultiFolderDialog filePaths: %@, fileCount: %@, directoryURL: %@, isCancelled: %d, isSuccess: %d", filePaths, fileCount, directoryURL, (int)isCancelled, (int)isSuccess]];
            
            // Convert NSArray to C array
            const char** cFilePaths = (const char**)malloc(filePaths.count * sizeof(char*));
            for (NSUInteger i = 0; i < filePaths.count; i++) {
                cFilePaths[i] = [filePaths[i] UTF8String];
            }
            
            if (isCancelled) {
                [Log d:TAG :@"showMultiFolderDialog was cancelled"];
                callback(NULL, -1, NULL, isCancelled, isSuccess, NULL);
            } else {
                [Log d:TAG :@"showMultiFolderDialog completed successfully"];
                callback(cFilePaths, (int)filePaths.count, directoryURL.UTF8String, isCancelled, isSuccess, NULL);
            }
            free(cFilePaths);
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showMultiFolderDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NULL, NO, NO, errorMessage.UTF8String);
        }
    }];
}

void showSaveFileDialog(const char* title,
                        const char* message,
                        const char* nameFieldStringValue,
                        const char** allowedContentTypes,
                        int contentTypesCount,
                        const char* directoryPath,
                        SaveFileDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showSaveFileDialog called with title: %s, message: %s, nameFieldStringValue: %s", title, message, nameFieldStringValue]];
    
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    NSString* nsNameFieldStringValue = [NSString stringWithUTF8String:nameFieldStringValue];
    
    // Convert allowedContentTypes array to NSArray
    NSMutableArray<NSString*>* nsAllowedContentTypes = [NSMutableArray array];
    for (int i = 0; i < contentTypesCount; i++) {
        NSString* contentType = [NSString stringWithUTF8String:allowedContentTypes[i]];
        [nsAllowedContentTypes addObject:contentType];
    }
    
    // Convert directoryPath to URL
    NSURL* directoryURL = nil;
    if (directoryPath != NULL && strlen(directoryPath) > 0) {
        directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directoryPath]];
    }
    
    [[UnityMacDialogManager shared] showSaveFileDialogWithTitle:nsTitle
                                                        message:nsMessage
                                            nameFieldStringValue:nsNameFieldStringValue
                                                allowedContentTypes:nsAllowedContentTypes
                                                       directoryURL:directoryURL
                                                         completion:^(NSDictionary* result, NSError* error) {
        if (result) {
            NSString* filePath = result[@"filePath"];
            NSNumber* fileCount = result[@"fileCount"];
            NSString* directoryURL = result[@"directoryURL"];
            BOOL isCancelled = [result[@"isCancelled"] boolValue];
            BOOL isSuccess = [result[@"isSuccess"] boolValue];
            [Log d:TAG :[NSString stringWithFormat:@"showSaveFileDialog filePath: %@, fileCount: %@, directoryURL: %@, isCancelled: %d, isSuccess: %d", filePath, fileCount, directoryURL, (int)isCancelled, (int)isSuccess]];
            
            if (isCancelled) {
                [Log d:TAG :@"showSaveFileDialog was cancelled"];
                callback(NULL, -1, NULL, isCancelled, isSuccess, NULL);
            } else {
                [Log d:TAG :@"showSaveFileDialog completed successfully"];
                callback(filePath.UTF8String, [fileCount intValue], directoryURL.UTF8String, isCancelled, isSuccess, NULL);
            }
        } else {
            NSString* errorMessage = error.localizedDescription ?: @"Unknown error";
            [Log e:TAG :[NSString stringWithFormat:@"showSaveFileDialog error occurred: %@", errorMessage]];
            callback(NULL, -1, NULL, NO, NO, errorMessage.UTF8String);
        }
    }];
}
