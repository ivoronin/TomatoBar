#!/bin/bash -e
PROJECT=TomatoBar.xcodeproj
SCHEME=TomatoBar
CONFIGURATION=Release
ARCHIVEPATH=TomatoBar.xcarchive

if [ "${CI}" ]; then
	CODE_SIGNING_ALLOWED="NO"
else
	CODE_SIGNING_ALLOWED="YES"
fi

npm i --python=python2.7

rm -rf "${ARCHIVEPATH}"
xcodebuild archive -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -archivePath "${ARCHIVEPATH}" CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED}"
[ "${CI}" ] || ./node_modules/.bin/create-dmg --overwrite "${ARCHIVEPATH}/Products/Applications/Tomato Bar.app"
