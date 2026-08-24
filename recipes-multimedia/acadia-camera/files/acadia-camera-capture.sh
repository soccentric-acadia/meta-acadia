#!/bin/sh
set -eu

if [ "${ENABLED:-0}" != "1" ]; then
    echo "camera capture is disabled; set ENABLED=1 in /etc/acadia/camera-capture.conf" >&2
    exit 0
fi

MODE="${MODE:-local}"

case "${MODE}" in
    local)
        # Render the V4L2 frame to a local sink (fakesink / autovideosink).
        exec gst-launch-1.0 -e \
            v4l2src device="${CAMERA_DEVICE:-/dev/video0}" ! \
            video/x-raw,width="${CAPTURE_WIDTH:-1280}",height="${CAPTURE_HEIGHT:-720}",framerate="${CAPTURE_FPS:-30}"/1 ! \
            videoconvert ! "${GST_SINK:-fakesink}"
        ;;
    udp)
        # V4L2 -> RTP/JPEG over UDP streaming bridge (hardware-enablement.md
        # §2).  Consume on the far end with, e.g.:
        #   gst-launch-1.0 udpsrc port="${STREAM_PORT:-5000}" \
        #       caps="application/x-rtp,encoding-name=JPEG,payload=26" ! \
        #       rtpjpegdepay ! jpegdec ! autovideosink
        exec gst-launch-1.0 -e \
            v4l2src device="${CAMERA_DEVICE:-/dev/video0}" ! \
            video/x-raw,width="${CAPTURE_WIDTH:-1280}",height="${CAPTURE_HEIGHT:-720}",framerate="${CAPTURE_FPS:-30}"/1 ! \
            videoconvert ! jpegenc ! rtpjpegpay ! \
            udpsink host="${STREAM_HOST:-127.0.0.1}" port="${STREAM_PORT:-5000}" sync=false
        ;;
    *)
        echo "camera capture: unknown MODE '${MODE}' (expected 'local' or 'udp')" >&2
        exit 1
        ;;
esac
