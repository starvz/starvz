#!/usr/bin/Rscript
options(crayon.enabled = FALSE)
suppressMessages(library(starvz))

# Options to help debug
# https://stackoverflow.com/questions/1975110/printing-stack-trace-and-continuing-after-error-occurs-in-r
options(keep.source = TRUE, error = quote({
  dump.frames()  # writes to last.dump
  n <- length(last.dump)
  if (n > 0) {
    calls <- names(last.dump)
    cat("Environment:\n", file = stderr())
    cat(paste0("  ", seq_len(n), ": ", calls), sep = "\n", file = stderr())
    cat("\n", file = stderr())
  }

  if (!interactive()) q()
}))

##############################
# Usage                      #
##############################
usage <- function ()
{
    stop("Usage: ", basename(commandArgs()[4]), "
         <directory> [application](optional) [use parquet](optional)\n
          where <directory> contains CSV files of the workflow;\n
          where [application](optional) is either cholesky or qrmumps.
          where [use parquet](optional) is a flag (1 to activate) to use parquet", call.=FALSE)
}

# Get the arguments to this script
args = commandArgs(trailingOnly=TRUE)

input.parquet = 1

if (length(args) < 1) {
    usage();
}else if (length(args) == 1) {
   input.application = "";
}else if (length(args) == 2) {
   input.application = args[[2]];
}else{
   input.application = args[[2]];
   input.parquet = args[[3]];
}

input.directory = args[[1]];

# This fixes some problems on recent versions of tidyverse
# Check: https://github.com/tidyverse/tidyr/issues/751
# Check: https://github.com/tidyverse/tidyr/issues/694
if(exists("unnest_legacy")){
  unnest <- unnest_legacy
}

if ( is.null(input.directory) ){
    usage();
}
if (input.application == "cholesky"){
    states.fun = cholesky_colors;
    states.filter = 2;
}else if (input.application == "qrmumps") {
    states.fun = qrmumps_colors;
    states.filter = 1;
}else if (input.application == "cholesky_pastix") {
    states.fun = cholesky_pastix_colors;
    states.filter = 1;
}else if (input.application == "cfd") {
    states.fun = cfd_colors;
    states.filter = 1;
}else if (input.application == "lu") {
    states.fun = lu_colors;
    states.filter = 2;
}else if (input.application == "qr") {
    states.fun = qr_colors;
    states.filter = 2;
}else if (input.application == "") {
    states.fun = qr_colors;
    states.filter = 0;
}

setwd(input.directory);

data <- starvz_phase1_read_write(directory = input.directory,
                             app_states_fun = states.fun,
                             state_filter = states.filter,
                             whichApplication = input.application,
                             input.parquet = input.parquet);
