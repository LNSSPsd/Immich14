#import <Foundation/Foundation.h>
#import "IMAssetFace.h"
#import "IMAssetFaceCreate.h"
#import "IMPerson.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMFaceApi : NSObject

+ (nullable NSURLSessionTask *)createFaceWithRequest:(IMAssetFaceCreate *)request
                                          completion:(void (^)(BOOL success,
                                                               NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)createFaceForAssetId:(NSString *)assetId
                                           personId:(NSString *)personId
                                        imageWidth:(NSInteger)imageWidth
                                       imageHeight:(NSInteger)imageHeight
                                                 x:(NSInteger)x
                                                 y:(NSInteger)y
                                              width:(NSInteger)width
                                             height:(NSInteger)height
                                         completion:(void (^)(BOOL success,
                                                              NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)facesForAssetId:(NSString *)assetId
                                    completion:(void (^)(NSArray<IMAssetFace *> *_Nullable faces,
                                                         NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)reassignFaceId:(NSString *)faceId
                                  toPersonId:(NSString *)personId
                                  completion:(void (^)(IMPerson *_Nullable person,
                                                       NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)deleteFaceId:(NSString *)faceId
                                      force:(BOOL)force
                                completion:(void (^)(BOOL success,
                                                     NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
