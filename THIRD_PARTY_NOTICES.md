# Third-party notices

Giggly's datasets, in `priv/datasets/`, and the glyph tables it measures text with, in
`priv/fonts/`, are copied from R packages. Each is listed with what was taken, where its data
comes from, and the licence it is used under, with that licence's full text. Each file's header
says how it was made.

## ggplot2 4.0.3 — MIT License

`priv/datasets/diamonds.csv`, `economics.csv`, `economics_long.csv`, `faithfuld.csv`, `mpg.csv`,
`msleep.csv` and `txhousing.csv` hold the datasets of those names as ggplot2 4.0.3 ships them,
written out by R. Their data comes from: diamonds, the prices of 53,940 diamonds, for which
ggplot2 names no source; economics and economics_long, the Federal Reserve Bank of St. Louis's
FRED database; faithfuld, ggplot2's density estimate of R's `faithful` data on the Old Faithful
geyser; mpg, the US Environmental Protection Agency's fuel economy data (fueleconomy.gov);
msleep, V. M. Savage and G. B. West, "A quantitative, theoretical framework for understanding
mammalian sleep", PNAS 104(3), 2007, with each mammal's order, conservation status and diet added
from Wikipedia; txhousing, the Texas A&M Real Estate Center.

```
MIT License

Copyright (c) 2025 ggplot2 core developer team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## vdiffr 1.0.9.9000 — MIT License

`priv/fonts/liberation_sans.txt` and `priv/fonts/symbola.txt` hold the `LIBERATION_DIM` and
`SYMBOLA_DIM` tables of vdiffr's `src/glyph_dims.h`, at commit
dc4f8127d8e857a2703d98bacd302ce697eacfb3 of https://github.com/r-lib/vdiffr: each glyph's width,
ascent and descent, which vdiffr measured from Liberation Sans Regular and Symbola Regular. They
are measurements of the fonts; no font file or glyph outline is included.

```
MIT License

Copyright (c) 2024 vdiffr authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mtcars, from R's datasets package

`priv/datasets/mtcars.csv` holds R's `mtcars` table as R 4.6.1's datasets package ships it,
written out by R: the fuel consumption and ten aspects of design and performance of 32 cars, from
the road tests of the 1974 Motor Trend US magazine, as published by H. V. Henderson and P. F.
Velleman, "Building multiple regression models interactively", Biometrics 37, 391-411, 1981. It
is the measurements alone; no code or text of R's is included.
