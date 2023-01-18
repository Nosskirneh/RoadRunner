#import <Foundation/Foundation.h>


#define NOW_PLAYING_APP_CHANGED_SELECTOR @selector(nowPlayingAppChanged:)
#define SET_RUNNING @selector(setRunning:)

#define kRoadRunnerRestoredMediaProcess "se.nosskirneh.roadrunner.restored-media-process"
#define kRoadRunnerSpringBoardRestarted "se.nosskirneh.roadrunner.springboard-restarted"


#ifdef __cplusplus
extern "C" {
#endif

BOOL isEnabled();

#ifdef __cplusplus
}
#endif
