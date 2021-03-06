library(ggplot2)

# set up themes for plotting
theme_ns = function() {
  return(theme_classic() + theme(aspect.ratio=1) + theme_blank_facet_label() + theme(legend.position = "bottom"))
}

theme_blank_facet_label = function() {
  return(theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), strip.background = element_blank()))
}
