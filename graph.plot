# SVG output
set terminal svg size 2520,800 dynamic font ",24" background rgb 'white'

#set title ARG1 font ",48"
set key outside bottom horizontal box center

# Identify the axes
#set xlabel "Runs"
#set ylabel "Value"

# The main data line
set style line 1 linecolor rgb '#0060ad' linetype 1 linewidth 3 \
  pointtype 7 pointsize .5
# Minimum line
set style line 5 linecolor rgb '#ff2020' linetype 1 linewidth 2
# Maximum line
set style line 6 linecolor rgb '#20ff20' linetype 1 linewidth 2

# Style for mean line
set style line 2 linecolor rgb '#e41a1c' linetype 2 linewidth 2 dashtype 2

# Style for the moving mean
set style line 3 linecolor rgb '#4060a0' linetype 1 linewidth 2 dashtype 3

# Style for the stake
set style line 4 linecolor rgb '#a0a000' linetype 1 linewidth 2 dashtype 4

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
plot ARG1 using 1:6 with lines linestyle 3 title "moving average", \
     ARG1 using 1:7 with lines linestyle 4 title "stake", \
     ARG2 + 0 with lines linestyle 2 title "mean", \
     ARG1 using 1:3 with lines linestyle 5 title "min", \
     ARG1 using 1:5 with lines linestyle 6 title "max", \
     ARG1 using 1:4:xticlabel(2) with linespoints linestyle 1 title "value"
