#include "Lifecycle.h"
void lg_lifecycle_suspend(LGLifecycle *state, LGSuspendReason reason, int selected_mode) {
    if (!state->blockers) state->mode = selected_mode;
    state->blockers |= (unsigned)reason;
}
bool lg_lifecycle_resume(LGLifecycle *state, LGSuspendReason reason) {
    unsigned before = state->blockers;
    state->blockers &= ~(unsigned)reason;
    return before != 0 && state->blockers == 0;
}
