# SVG output
set terminal svg size 2520,800 dynamic font ",24" background rgb 'white'

#set title ARG1 font ",48"
set key outside bottom horizontal box center

# The main data line
set style line 1 linecolor rgb '#0060ad' linetype 1 linewidth 3 \
  pointtype 7 pointsize .5
# Trend
set style line 2 linecolor rgb '#ff2020' linetype 1 linewidth 5

set grid
unset border

# Add Y margins above and below the auto-scaled plot area
# Syntax: set offset <left>, <right>, <top>, <bottom>
set offset 0, 0, graph 0.25, graph 0.05

# add a little margin below the plot to move out the key
set bmargin 5

set xtics rotate 1 out nomirror
set ytics out font ",24" nomirror

set format y "%.2s %c"

set datafile separator ";"
plot ARG1 using 1:8 with lines linestyle 2 title "trend", \
     ARG1 using 1:4:xticlabel(2) with linespoints linestyle 1 title "value"
