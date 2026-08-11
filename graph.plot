# SVG output
set terminal svg size 2520,580 dynamic font ",24" background rgb 'white'

#set title ARG1 font ",48"
set key outside bottom horizontal

# Identify the axes
#set xlabel "Runs"
#set ylabel "Value"

# The main data line
set style line 1 linecolor rgb '#0060ad' linetype 1 linewidth 3 \
  pointtype 7 pointsize .5

# Style for average line
set style line 2 linecolor rgb '#e41a1c' linetype 2 linewidth 2 dashtype 2

# Style for the moving average
set style line 3 linecolor rgb '#40b040' linetype 1 linewidth 2 dashtype 2

# Style for the stake
set style line 4 linecolor rgb '#a0a000' linetype 1 linewidth 2 dashtype 2

set grid
unset border

# Add Y margins above and below the auto-scaled plot area
# Syntax: set offset <left>, <right>, <top>, <bottom>
set offset 0, 0, graph 0.25, graph 0.05

set xtics 1 out
set ytics out

set format y "%.2s %c"
set format x ""

set datafile separator ";"
plot ARG1 using 1:3 with linespoints linestyle 1 title "", \
     ARG1 using 1:3:2 with labels title "" font ", 24" rotate left tc lt 2, \
     ARG1 using 1:4 with lines linestyle 3 title "moving average", \
     ARG1 using 1:5 with lines linestyle 4 title "stake", \
     ARG2 + 0 with lines linestyle 2 title "average"
