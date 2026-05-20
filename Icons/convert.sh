#!/bin/bash -e
ASSETS_PATH=../TomatoBar/Assets.xcassets
BARICON_SRC=tomato-filled.png
BARICON_ICONSET_IDLE=${ASSETS_PATH}/BarIconIdle.imageset
BARICON_ICONSET_WORK=${ASSETS_PATH}/BarIconWork.imageset
BARICON_ICONSET_SHORT_REST=${ASSETS_PATH}/BarIconShortRest.imageset
BARICON_ICONSET_LONG_REST=${ASSETS_PATH}/BarIconLongRest.imageset
BARICON_FONT_NAME=SF-Compact-Rounded-Black
BARICON_FONT_SIZE_BASE=8
BARICON_TEXT_OFFSET_BASE=3

CONVERT="convert -verbose -background none +repage"

function convert_baricon() {
    ICONSET_NAME=$1
    ANNOTATE_TEXT=$2

    for SCALE in $(seq 1 3); do
        IMAGE_SIZE="!$((16*SCALE))x$((16*SCALE))"
        POINT_SIZE=$((BARICON_FONT_SIZE_BASE*SCALE))
        OFFSET_X=1
        OFFSET_Y=$((BARICON_TEXT_OFFSET_BASE*SCALE))
        SCALE_NAME="@${SCALE}x"
        if [ ${SCALE} -eq 1 ]; then
            SCALE_NAME=""
        fi
        DEST_NAME="${ICONSET_NAME}/icon_16x16${SCALE_NAME}.png"
        if [ -n "${ANNOTATE_TEXT}" ]; then
            ${CONVERT} -resize "${IMAGE_SIZE}" -font ${BARICON_FONT_NAME} -pointsize ${POINT_SIZE} \
                -fill transparent -gravity center -annotate +${OFFSET_X}+${OFFSET_Y} ${ANNOTATE_TEXT} \
                ${BARICON_SRC} ${DEST_NAME}
        else
            ${CONVERT} -resize "${IMAGE_SIZE}" ${BARICON_SRC} ${DEST_NAME}
        fi
    done
}

if [ "$1" == "baricon" ]; then
    export LC_CTYPE="en_US.UTF-8" # Silences fontconfig warning

    convert_baricon ${BARICON_ICONSET_IDLE} ''
    convert_baricon ${BARICON_ICONSET_WORK} 'W'
    convert_baricon ${BARICON_ICONSET_SHORT_REST} 'R'
    convert_baricon ${BARICON_ICONSET_LONG_REST} 'L'
fi
