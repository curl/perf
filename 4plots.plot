# SVG output
set terminal svg size 2520,800 dynamic font ",24" background rgb 'white'
set key outside bottom horizontal box center

set style line 1 linecolor rgb '#0060ad' linetype 1 linewidth 3
set style line 2 linecolor rgb '#a060ad' linetype 1 linewidth 3
set style line 3 linecolor rgb '#a0a0ad' linetype 1 linewidth 3
set style line 4 linecolor rgb '#a06000' linetype 1 linewidth 3

set grid
unset border

# add a little margin below the plot to move out the key
set bmargin 5

set xtics rotate 1 out nomirror
set ytics out font ",24" nomirror

set format y "%.2s %c"

set datafile separator ";"
plot ARG1 using 1:4 with lines linestyle 1 title "HTTP/1", \
     ARG2 using 1:4 with lines linestyle 2 title "HTTP/2", \
     ARG3 using 1:4 with lines linestyle 3 title "HTTP/3", \
     ARG4 using 1:4:xticlabel(2) with linespoints linestyle 4 title "FTPS"

#     ARG4 using 1:4 with lines linestyle 4 title "FTPS"
