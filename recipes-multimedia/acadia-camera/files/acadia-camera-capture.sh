#!/bin/sh
set -eu

if [ "${ENABLED:-0}" != "1" ]; then
    echo "camera capture is disabled; set ENABLED=1 in /etc/acadia/camera-capture.conf" >&2
    exit 0
fi

exec gst-launch-1.0 -e \
    v4l2src device="${CAMERA_DEVICE:-/dev/video0}" ! \
    video/x-raw,width="${CAPTURE_WIDTH:-1280}",height="${CAPTURE_HEIGHT:-720}",framerate="${CAPTURE_FPS:-30}"/1 ! \
    videoconvert ! "${GST_SINK:-fakesink}"
