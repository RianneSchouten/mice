#'\code{mipo}: Multiple imputation pooled object
#'
#' The \code{mipo} object contains the results of the pooling step. 
#' The function \code{\link{pool}} generates an object of class \code{mipo}.
#' 
#' @param x An object of class \code{mipo}
#' @param object An object of class \code{mipo}
#' @param mira.obj An object of class \code{mira}
#' @inheritParams broom::lm_tidiers
#' @param z Data frame with a tidied version of a coefficient matrix
#' @param conf.int Logical indicating Wwether to include 
#' a confidence interval. The default is \code{FALSE}.
#' @param conf.level Confidence level of the interval, used only if
#' \code{conf.int = TRUE}. Number between 0 and 1.
#' @param exponentiate Flag indicating whether to exponentiate the 
#' coefficient estimates and confidence intervals (typical for 
#' logistic regression).
#' @param \dots Arguments passed down
#' @details An object class \code{mipo} is a \code{list} with three 
#' elements: \code{call}, \code{m} and \code{pooled}.
#' 
#' The \code{pooled} elements is a data frame with columns:
#' \tabular{ll}{
#' \code{qbar}    \tab Pooled complete data estimate\cr
#' \code{ubar}    \tab Within-imputation variance of \code{qbar}\cr
#' \code{b}       \tab Between-imputation variance of \code{qbar}\cr
#' \code{t}       \tab Total variance, of \code{qbar}\cr
#' \code{dfcom}   \tab Degrees of freedom in complete data\cr
#' \code{df}      \tab Degrees of freedom of $t$-statistic\cr
#' \code{riv}     \tab Relative increase in variance\cr
#' \code{lambda}  \tab Proportion attributable to the missingness\cr
#' \code{fmi}     \tab Fraction of missing information\cr
#' }
#' The names of the terms are stored as \code{row.names(pooled)}.
#' 
#' The \code{process_mipo} is a helper function to process a 
#' tidied mipo object, and is normally not called directly.
#' It adds a confidence interval, and optionally exponentiates, the result.
#'@seealso \code{\link{pool}}, 
#'\code{\link[=mids-class]{mids}}, \code{\link[=mira-class]{mira}}
#'@references van Buuren S and Groothuis-Oudshoorn K (2011). \code{mice}:
#'Multivariate Imputation by Chained Equations in \code{R}. \emph{Journal of
#'Statistical Software}, \bold{45}(3), 1-67.
#'\url{http://www.jstatsoft.org/v45/i03/}
#'@keywords classes
#' @name mipo
NULL

#'@rdname mipo
#'@export
mipo <- function(mira.obj, ...) {
  if (!is.mira(mira.obj)) stop("`mira.obj` not of class `mira`")
  structure(pool(mira.obj, ...), class = c("mipo"))
}

#'@return The \code{summary} method returns a data frame with summary statistis of the pooled analysis.
#'@rdname mipo
#'@export
summary.mipo <- function(object, conf.int = FALSE, conf.level = .95,
                         exponentiate = FALSE, ...) {
  m <- object$m
  z <- with(object$pooled, data.frame(
    estimate  = qbar,
    std.error = sqrt(t),
    statistic = qbar / sqrt(t),
    df        = df,
    p.value   = if (all(df > 0)) 
      2 * (1 - pt(abs(qbar / sqrt(t)), df)) else NA,
    riv       = (1 + 1 / m) * b / ubar,
    lambda    = (1 + 1 / m) * b / t,
    stringsAsFactors = FALSE,
    row.names = row.names(object$pooled)))
  z$fmi <- (z$riv + 2 / (z$df + 3)) / (z$riv + 1)
  
  z <- process_mipo(z, object, conf.int = conf.int, conf.level = conf.level,
                    exponentiate = exponentiate)
  class(z) <- c("mipo.summary", "data.frame")
  z
}

#'@rdname mipo
#'@export
print.mipo <- function(x, ...) {
  cat("Class: mipo    m =", x$m, "\n")
  print.data.frame(x$pooled, ...)
  invisible(x)
}

#'@rdname mipo
#'@export
print.mipo.summary <- function(x, ...) {
  print.data.frame(x, ...)
  invisible(x)
}

#' @rdname mipo
#' @keywords internal
process_mipo <- function(z, x, conf.int = FALSE, conf.level = .95,
                         exponentiate = FALSE) {
  if (exponentiate) {
    # save transformation function for use on confidence interval
    if (is.null(x$family) ||
        (x$family$link != "logit" && x$family$link != "log")) {
      warning(paste("Exponentiating coefficients, but model did not use",
                    "a log or logit link function"))
    }
    trans <- exp
  } else {
    trans <- identity
  }
  
  if (conf.int) {
    # avoid "Waiting for profiling to be done..." message
    CI <- suppressMessages(confint(x, level = conf.level))
    # Handle case if regression is rank deficient
    p <- x$rank
    if (!is.null(p) && !is.null(x$qr)) {
      piv <- x$qr$pivot[seq_len(p)]
      CI <- CI[piv, , drop = FALSE]
    }
    z <- cbind(z[, 1:5], trans(unrowname(CI)), z[, 6:8])
  }
  z$estimate <- trans(z$estimate)
  
  z
}

vcov.mipo <- function(object, ...) {
  so <- diag(object$t)
  dimnames(so) <- list(object$term, object$term)
  so
}

confint.mipo <- function(object, parm, level = 0.95, ...) {
  pooled <- object$pooled
  cf <- pooled$qbar
  df <- pooled$df
  se <- sqrt(pooled$t)
  pnames <- names(df) <- names(se) <- names(cf) <- row.names(pooled)
  if (missing(parm)) 
    parm <- pnames
  else if (is.numeric(parm)) 
    parm <- pnames[parm]
  a <- (1 - level)/2
  a <- c(a, 1 - a)
  fac <- qt(a, df)
  pct <- format.perc(a, 3)
  ci <- array(NA, dim = c(length(parm), 2L), 
              dimnames = list(parm, pct))
  ci[, 1] <- cf[parm] + qt(1 - a, df[parm]) * se[parm]
  ci[, 2] <- cf[parm] + qt(a, df[parm]) * se[parm]
  ci
}

unrowname <- function (x) 
{
  rownames(x) <- NULL
  x
}

format.perc <- function (probs, digits) 
  paste(format(100 * probs, trim = TRUE, scientific = FALSE, digits = digits), 
        "%")
