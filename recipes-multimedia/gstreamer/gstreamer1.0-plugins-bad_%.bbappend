# Enable the GStreamer V4L2 stateless codec elements (v4l2codecs) so the
# RPi5/CM5 hardware H.265/HEVC decode path is available (task.md
# Camera/Video).  The matching 'commercial' license flag is accepted in
# kas/common.yaml (LICENSE_FLAGS_ACCEPTED ?= "commercial").
PACKAGECONFIG:append = " v4l2codecs"
