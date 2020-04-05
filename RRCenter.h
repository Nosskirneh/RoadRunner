@interface RRCenter : NSObject
@property (nonatomic, readonly) NSString *centerName;
+ (instancetype)centerNamed:(NSString *)name;
- (void)addTarget:(id)target action:(SEL)action;
- (void)removeAction:(SEL)action;

/* Asynchronously call a void method. */
- (void)callExternalVoidMethod:(SEL)method
                 withArguments:(NSDictionary *)args;

/* Synchronously call a method and recieve the return value. */
- (id)callExternalMethod:(SEL)method
           withArguments:(NSDictionary *)args;

/* Asynchronously call a method and receive the return value
   in the completion handler. */
- (void)callExternalMethod:(SEL)method
             withArguments:(NSDictionary *)args
                completion:(void(^)(id))completionHandler;
@end
