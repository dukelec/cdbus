#!/bin/bash

cd "$(dirname "$0")"

convert -resize 100% -density 160 -quality 80% -delay 200 -loop 0 *.svg ../operation.gif

