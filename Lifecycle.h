#ifndef LIDGLOW_LIFECYCLE_H
#define LIDGLOW_LIFECYCLE_H
#include <stdbool.h>
typedef enum {
    LGSuspendDisplay = 1u << 0,
    LGSuspendSystem = 1u << 1,
    LGSuspendLock = 1u << 2
} LGSuspendReason;
typedef struct {
    unsigned blockers;
    int mode;
} LGLifecycle;
/* Save the selected mode once, including a Music/Auto startup still in flight. */
void lg_lifecycle_suspend(LGLifecycle *state, LGSuspendReason reason, int selected_mode);
/* A display waking cannot resume capture while the system is asleep or locked. */
bool lg_lifecycle_resume(LGLifecycle *state, LGSuspendReason reason);
#endif
