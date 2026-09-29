# Driver de teste (Perl): o script foi cortado antes do SDL_Init.
open my $fh, '<', $ARGV[0] or die;
while (<$fh>) {
    my @p = split;
    if ($p[0] eq 'init') {  # saque fixo: direção e velocidade inteiras
        reset_ball($p[1]);
        $g{serve_timer} = 0;
        ($g{vx}, $g{vy}) = ($p[2], $p[3]);
        next;
    }
    my @keys = (0) x 512;
    $keys[$_] = 1 for $p[1] eq '-' ? () : split /,/, $p[1];
    update(\@keys, STEP) for 1 .. $p[0];
}
printf "left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f\n",
    @g{qw(left_y right_y bx by vx vy speed score_l score_r serve_timer)};
