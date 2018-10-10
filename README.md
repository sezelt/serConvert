# serConvert
MATLAB utility to convert *.ser files to images with optional scalebar.

## Usage
`img = serConvert(...)`

Options:

* `fname`: `*.ser` file name. If you do not specify `fname` a GUI file selection dialog will open.
* `scalebar`: `'on'`/`'off'` (default: on) Whether to burn scalebar into image.
* `save`: true/false (default: true) Save image file with same name as `*.ser` file in current directory.
* `format`: `'png'`,`'jpeg'`,`'tiff'`, etc (default: png) File format to save output image. Accepts any valid format for `imwrite`.
* `power`: float (default: 0.5) Gamma correction for image. 0.5 seems to give the usual contrast.
* `scaleColor`: 0.0-1.0 (default: auto) Intensity of the scalebar and text. Defaults to auto choice between 0 and 1, depending on the background intensity in the area of the image with the scalebar.
* `show`: `'on'`/`'off'` (default: off) Display final image.

Returns `img`, the read out image with the gamma correction, scaled to [0,1], and as a double precision float.
