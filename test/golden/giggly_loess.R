# Not a golden: the loess the smooth_loess goldens draw, sourced by each. ggplot2's geom_smooth()
# fits it as Giggly does (design-log §4, the entries beginning "loess is Giggly's own", "A loess band
# takes its first trace" and "A loess curve stops at its rows"): R's loess() fitted directly at each
# place (surface = "direct") with exact statistics, its band's t quantile at the first trace's
# degrees of freedom, R's one.delta, where R's predict() reads one.delta² / two.delta, and the
# places outside the rows missing, as R's default surface leaves them. Everything else, the band,
# the line and the key, is ggplot2's own.
library(ggplot2)
giggly_loess <- function(formula, data, weights, span = 0.75, ...) {
  data$row_weights <- eval(substitute(weights), data, parent.frame())
  model <- loess(formula, data, weights = row_weights, span = span,
                 control = loess.control(surface = "direct", statistics = "exact"))
  class(model) <- c("giggly_loess", class(model))
  model
}
predictdf.giggly_loess <- function(model, xseq, se, level) {
  pred <- stats::predict(model, newdata = data.frame(x = xseq), se = se)
  outside <- xseq < min(model$x) | xseq > max(model$x)
  if (se) {
    y <- pred$fit
    ci <- pred$se.fit * stats::qt(level / 2 + 0.5, model$one.delta)
    out <- data.frame(x = xseq, y = y, ymin = y - ci, ymax = y + ci, se = pred$se.fit)
  } else {
    out <- data.frame(x = xseq, y = as.vector(pred))
  }
  out[outside, -1] <- NA
  out
}
registerS3method("predictdf", "giggly_loess", predictdf.giggly_loess, envir = asNamespace("ggplot2"))
