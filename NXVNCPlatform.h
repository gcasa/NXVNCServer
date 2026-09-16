/* Native input selection. Modern macOS must retain the view-only fallback. */
#ifndef NXVNC_PLATFORM_H
#define NXVNC_PLATFORM_H
#if defined(NXVNC_INPUT_INTEL_TEST) || \
    ((defined(i386) || defined(__i386__)) && !defined(__APPLE__))
#define NXVNC_INPUT_INTEL 1
#endif
#endif
