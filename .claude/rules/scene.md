---
paths:
  - "lib/giggly/scene.ex"
  - "lib/giggly/scene/**"
---

# The scene

`Giggly.Scene` is what a plot draws, independent of any output format: a table of tracks whose
cells hold primitives. Why it is a table from the first drawing, and what waits: design-log §4,
the entry beginning "The coordinate system arrives with drawing"; why there is a scene between
rendering and SVG at all: the entry beginning "Three top-level values".

## Rules

- **A scene is values and calls nothing.** Its boundary lists nothing and exports the structs
  rendering builds and a backend reads (`Cell`, `Points`); nothing in it knows SVG.
- **Primitives are placed in their cell's units, 0 to 1 across and up, and sized in points.** A
  primitive never knows the cell's size; the backend places it in the cell's box.
- **A track's size is a weight** (ggplot2's `"null"` unit). Until the first cell beside the
  panel, a scene is one row and one column track holding the panel's cell, and `SVG.draw/3`
  refuses any other shape: several tracks sharing the drawing, absolute and measured tracks,
  spanning cells, names, clipping and z-order arrive with their first reader (axes, titles,
  legends), and with measured tracks a text-metrics service.
- **A cell sits at a row and a column, counting from 1.** The layout's `row` and `column` put a
  panel's cell there.

## How it works

`%Giggly.Scene{}` holds the column tracks (`widths`, left to right), the row tracks (`heights`,
top to bottom) and the cells. `Scene.Cell` holds a row, a column and its primitives in drawing
order. `Scene.Points` is grid's `pointsGrob()` for shape 19: the positions, one radius, one
outline width and one colour.
