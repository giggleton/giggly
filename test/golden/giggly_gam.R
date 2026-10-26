# Not a golden: the gam the smooth_gam goldens draw, sourced by each. ggplot2's geom_smooth() fits
# it as Giggly does (design-log §4, the entries beginning "gam is Giggly's own" and "A gam's
# shrinkage"): mgcv's own REML gam of the model ggplot2 fits, y ~ s(x, bs = "cs"), but with the
# cubic regression spline's two unpenalised directions, the constant and the straight line through
# its knots, each penalised by 0.055 of its penalty's smallest positive eigenvalue, where mgcv's
# "cs" gives them 0.1 and 0.01 along whichever two directions its eigen-decomposition's rounding
# picks. mgcv builds the "cr" basis and penalty, the curve is held to sum to 0 over the rows as
# mgcv holds it, and mgcv fits it by REML through `paraPen`, run to a far tighter tolerance than
# its default, so the golden is REML's least rather than wherever mgcv's default stops near it.
# The band is the curve ∓ the normal quantile at the level times the standard error, as ggplot2
# reads a gam's band through its `predictdf()` for a glm. Everything else, the band, the line and
# the key, is ggplot2's own. A group mgcv cannot fit, of fewer than 10 distinct x say, fails here
# as it fails there, and ggplot2 draws it nothing.
suppressMessages(library(mgcv))
library(ggplot2)
giggly_gam <- function(formula, data, weights, ...) {
  data$row_weights <- eval(substitute(weights), data, parent.frame())
  data <- data[!is.na(data$row_weights), ]
  basis <- smoothCon(s(x, bs = "cr"), data, absorb.cons = FALSE, scale.penalty = FALSE)[[1]]
  values <- eigen(basis$S[[1]], symmetric = TRUE)$values
  constant <- rep(1, 10) / sqrt(10)
  line <- basis$xp - mean(basis$xp)
  line <- line / sqrt(sum(line^2))
  penalty <- basis$S[[1]] + 0.055 * values[8] * (tcrossprod(constant) + tcrossprod(line))
  sweep <- qr.Q(qr(matrix(colSums(basis$X), ncol = 1)), complete = TRUE)[, -1]
  fitting <- list(y = data$y, w = data$row_weights, X = basis$X %*% sweep)
  model <- gam(y ~ X, data = fitting, weights = w, method = "REML",
               paraPen = list(X = list(t(sweep) %*% penalty %*% sweep)),
               control = gam.control(epsilon = 1e-14,
                                     newton = list(conv.tol = 1e-14, maxNstep = 5, maxHalf = 60)))
  structure(list(model = model, basis = basis, sweep = sweep), class = "giggly_gam")
}
predictdf.giggly_gam <- function(model, xseq, se, level) {
  X <- cbind(1, PredictMat(model$basis, data.frame(x = xseq)) %*% model$sweep)
  fit <- as.vector(X %*% coef(model$model))
  if (se) {
    error <- sqrt(rowSums((X %*% model$model$Vp) * X))
    reach <- stats::qnorm(level / 2 + 0.5) * error
    data.frame(x = xseq, y = fit, ymin = fit - reach, ymax = fit + reach, se = error)
  } else {
    data.frame(x = xseq, y = fit)
  }
}
registerS3method("predictdf", "giggly_gam", predictdf.giggly_gam, envir = asNamespace("ggplot2"))
