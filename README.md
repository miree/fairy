# FAIRY - flexible analysis of irradiation yields

Fairy is a light-weight data visualization and analysis tool. It is meant to be used with the [Elder](https://git.gsi.de/eel-software/elder/elderpt) data analysis framework.

The Design goals of fairy were:
  - quick response in interactive use 
  - fast update rates
  - intuitive interface
  - few dependencies (e.g. fairy does not use Root)

Features are:
  - 1D/2D histograms 
  - 1D/2D window gates and 2D polygon gates
  - 1D functions and interactive fitting to histogram data
  - interactive projections of 2D histograms

The program is written in the D programming language. The GUI is currently based on GTK3 and Cairo.

## User Manual

fairy manages multiple data windows. Each window is separated into 
  - a tree-view of all available items, 
  - a canvas where items are visualized,
  - and below the canvas is a control panel.

When a check box in the tree-view is clicked, the current status of the item will be shown. 
If the check box is a directory with multiple items, all items will be shown.
If the item is a histogram which is changing because data is analyzed, the canvas will show the state of the histogram when the check box was clicked.
Pressing the "refr." button in the control panel will update the drawing of the histogram once.
In "auto refr." mode, the drawing of all items will be updated repeatedly as fast as possible.



Each window can display data (1D/2D histograms, 1D/2D gates, 1D functions) in tree modes
 - overlay mode: all data is drawn on top of each other
 - row-major mode: dat


## keyboard shortcuts

| key      | action                                                                        |
|----------|-------------------------------------------------------------------------------|
| Ctrl-n   | open new window                                                               |
| Ctrl-w   | close window                                                                  |
| Ctrl-q   | quit program                                                                  |
|   u      | update content                                                                |
|   p      | toggle poll mode (aka auto update)                                            |
|   f      | fit viewport to content                                                       |
|   x      | toggle auto fit mode on x axis                                                |
|   y      | toggle auto fit mode on y axis                                                |
|   z      | toggle auto fit mode on z axis                                                |
|   l      | toggle logscale mode (affects y or z axis)                                    |
|   g      | toggle grid                                                                   |
|   i      | toggle fill mode for 1D histograms                                            |
|   t      | toggle statistics display for 1D histograms                                   |
|   m      | toggle zoom mode (only filled bins are considered when fitting the viewport)  |
|   o      | overlay mode (no tiling, all histograms are drawn on top of each other)       |
|   r      | row-major mode                                                                |
|   c      | column-major mode                                                             |
| 1...9    | set number of rows/columns in row-/column-major mode                          |
|   b      | toggle color bar                                                              |
| a,s,d,w  | navigate the viewport                                                         |
|  e,q     | zoom in/out                                                                   |
