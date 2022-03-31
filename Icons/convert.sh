#!/bin/bash -e
ASSETS_PATH=../TomatoBar/Assets.xcassets
APPICON_SRC=TomatoBar.png
APPICON_ICONSET=${ASSETS_PATH}/AppIcon.appiconset
BARICON_SRC=tomato-filled.png
BARICON_ICONSET=${ASSETS_PATH}/BarIcon.imageset

CONVERT="convert -background none -trim +repage"

set -x

if [ "$1" == "appicon" ]; then
    ${CONVERT} -resize '!16x16' ${APPICON_SRC} ${APPICON_ICONSET}/icon_16x16.png
    ${CONVERT} -resize '!32x32' ${APPICON_SRC} ${APPICON_ICONSET}/icon_16x16@2x.png
    ${CONVERT} -resize '!32x32' ${APPICON_SRC} ${APPICON_ICONSET}/icon_32x32.png
    ${CONVERT} -resize '!64x64' ${APPICON_SRC} ${APPICON_ICONSET}/icon_32x32@2x.png
    ${CONVERT} -resize '!128x128' ${APPICON_SRC} ${APPICON_ICONSET}/icon_128x128.png
    ${CONVERT} -resize '!256x256' ${APPICON_SRC} ${APPICON_ICONSET}/icon_128x128@2x.png
    ${CONVERT} -resize '!256x256' ${APPICON_SRC} ${APPICON_ICONSET}/icon_256x256.png
    ${CONVERT} -resize '!512x512' ${APPICON_SRC} ${APPICON_ICONSET}/icon_256x256@2x.png
    ${CONVERT} -resize '!512x512' ${APPICON_SRC} ${APPICON_ICONSET}/icon_512x512.png
    ${CONVERT} -resize '!1024x1024' ${APPICON_SRC} ${APPICON_ICONSET}/icon_512x512@2x.png
fi

if [ "$1" == "baricon" ]; then
    ${CONVERT} -resize '!16x16' ${BARICON_SRC} ${BARICON_ICONSET}/icon_16x16.png
    ${CONVERT} -resize '!32x32' ${BARICON_SRC} ${BARICON_ICONSET}/icon_16x16@2x.png
    ${CONVERT} -resize '!48x48' ${BARICON_SRC} ${BARICON_ICONSET}/icon_16x16@3x.png
fi
