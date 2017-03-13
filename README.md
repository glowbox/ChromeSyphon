# ChromeSyphon


Render any web content as a Syphon source.

This project is based on the example MacOS project included with the Chromium Embedded Framework. It is inspired by the [CefWithSyphon](https://github.com/vibber/CefWithSyphon) project but includes many additional configuration options by way of a JSON configuration file.

## Current Release

[Download the latest release here.](https://github.com/glowbox/ChromeSyphon/releases/download/v1.0/ChromeSyphon-build.zip)

**Note:** Builds are provided as-is, this tool has not been extensively tested.

## Configuration 

This application will look for a file called `config.json` in the same folder with the app package. 

Configuration options include:

| Property | Type | Description 
| -------- | ---- | -----------
| url      | string | The URL to load at startup
| content-width | integer | Witdh of the browser content in pixels.
| content-height | integer | Height of the browser content in pixels.
| window-x | integer | Horizontal position of the window at startup.
| window-y | integer | Vertical of the window at startup.
| start-minimized | boolean | If true, the window will minimze to the dock at startup.
| allow-window-resize | boolean | If true, the window will be resizable.
| syphon-name | string | The name of the syphon source.


## Building the Project

Building this project requires the Chrome Embedded Framework (which is enormous so it's not included in this repository).

To build:

 1. Clone this repository.
 2. [Download and unzip the Mac 32 bit release from branch 1547 ](https://cefbuilds.com/)
 3. Copy the contents of the CEF zip into a folder named `CEF` in the root of the project
 4. Open the xcode project and build it.
 
 
## Credits

This project was made possible by the efforts of many other talented people:

[The amazing Syphon Framework](Syphon framework was built by Vade.https://github.com/Syphon/Syphon-Framework) by [Vade](https://github.com/vade)

[Chromium Embedded Framework](https://bitbucket.org/chromiumembedded/cef)