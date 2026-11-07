#include "Lifecycle.h"
#include <assert.h>
#include <stdio.h>
static const LGSuspendReason reasons[] = {LGSuspendDisplay, LGSuspendSystem, LGSuspendLock};
int main(void) {
    for (int mode = 0; mode < 6; ++mode) {
        for (int first = 0; first < 3; ++first) {
            LGLifecycle state = {0};
            assert(!lg_lifecycle_resume(&state, reasons[first]));
            lg_lifecycle_suspend(&state, reasons[first], mode);
            lg_lifecycle_suspend(&state, reasons[first], 0); /* Duplicate must not lose mode. */
            assert(state.mode == mode);
            assert(lg_lifecycle_resume(&state, reasons[first]));
            assert(!lg_lifecycle_resume(&state, reasons[first]));
            assert(state.mode == mode);
        }
        for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) {
            if (a == b) continue;
            int c = 3-a-b;
            LGLifecycle state = {0};
            lg_lifecycle_suspend(&state, reasons[a], mode);
            lg_lifecycle_suspend(&state, reasons[b], 0);
            lg_lifecycle_suspend(&state, reasons[c], 0);
            assert(!lg_lifecycle_resume(&state, reasons[a]));
            assert(!lg_lifecycle_resume(&state, reasons[b]));
            assert(state.mode == mode && state.blockers == (unsigned)reasons[c]);
            assert(lg_lifecycle_resume(&state, reasons[c]));
            assert(!state.blockers && state.mode == mode);
            lg_lifecycle_suspend(&state, LGSuspendDisplay, (mode + 1) % 6);
            assert(lg_lifecycle_resume(&state, LGSuspendDisplay));
            assert(state.mode == (mode + 1) % 6); /* A later cycle saves the new choice. */
        }
    }
    puts("PASS: all modes, screen/system/lock ordering, duplicate events, no early resume and repeated cycles");
}
