package MondayCalendar::Tags;

use strict;

use MT;
use MT::Util qw( start_end_month offset_time_list wday_from_ts days_in );

sub hdlr_monday_calendar {
    my ( $ctx, $args, $cond ) = @_;
    my $blog_id = $ctx->stash('blog_id');
    my ($prefix);
    my @ts = offset_time_list( time, $blog_id );
    my $today = sprintf "%04d%02d", $ts[5] + 1900, $ts[4] + 1;
    if ( $prefix = lc( $args->{month} || '' ) ) {
        if ( $prefix eq 'this' ) {
            my $ts = $ctx->{current_timestamp}
                or return $ctx->error(
                MT->translate(
                    "You used an [_1] tag without a date context set up.",
                    qq(<MTCalendar month="this">)
                )
                );
            $prefix = substr $ts, 0, 6;
        }
        elsif ( $prefix eq 'last' ) {
            my $year  = substr $today, 0, 4;
            my $month = substr $today, 4, 2;
            if ( $month - 1 == 0 ) {
                $prefix = $year - 1 . "12";
            }
            else {
                $prefix = $year . $month - 1;
            }
        }
        else {
            return $ctx->error(
                MT->translate("Invalid month format: must be YYYYMM") )
                unless length($prefix) eq 6;
        }
    }
    else {
        $prefix = $today;
    }
    my ( $cat_name, $cat );
    if ( $cat_name = $args->{category} ) {
        $cat
            = MT::Category->load(
            { label => $cat_name, blog_id => $blog_id } )
            or return $ctx->error(
            MT->translate( "No such category '[_1]'", $cat_name ) );
    }
    else {
        $cat_name = '';    ## For looking up cached calendars.
    }
    my $uncompiled     = $ctx->stash('uncompiled') || '';
    my $r              = MT::Request->instance;
    my $calendar_cache = $r->cache('calendar');
    unless ($calendar_cache) {
        $r->cache( 'calendar', $calendar_cache = {} );
    }

    my $week = {
        'mon' => 1,
        'tue' => 2,
        'wed' => 3,
        'thu' => 4,
        'fri' => 5,
        'sat' => 6,
        'sun' => 0,
    };
    my $first = $args->{first} ? $args->{first} : 'mon';

    if ( exists $calendar_cache->{ $blog_id . ":" . $first . $prefix . $cat_name }
        && $calendar_cache->{ $blog_id . ":" . $first . $prefix . $cat_name }{'uc'} eq
        $uncompiled )
    {
        return $calendar_cache->{ $blog_id . ":" . $first . $prefix . $cat_name }
            {output};
    }
    $today .= sprintf "%02d", $ts[3];
    my ( $start, $end ) = start_end_month($prefix);
    my ( $y, $m ) = unpack 'A4A2', $prefix;
    my $days_in_month = days_in( $m, $y );

    my $pad_start = (wday_from_ts( $y, $m, 1 ) + 7 - $week->{$first}) % 7;
    my $pad_end = 6 - (wday_from_ts( $y, $m, $days_in_month ) + 7 - $week->{$first}) % 7;

    my $iter = MT::Entry->load_iter(
        {   blog_id     => $blog_id,
            authored_on => [ $start, $end ],
            status      => MT::Entry::RELEASE()
        },
        {   range_incl => { authored_on => 1 },
            'sort'     => 'authored_on',
            direction  => 'ascend',
        }
    );
    my @left;
    my $res          = '';
    my $tokens       = $ctx->stash('tokens');
    my $builder      = $ctx->stash('builder');
    my $iter_drained = 0;

    for my $day ( 1 .. $pad_start + $days_in_month + $pad_end ) {
        my $is_padding = $day < $pad_start + 1
            || $day > $pad_start + $days_in_month;
        my ( $this_day, @entries ) = ('');
        local (
            $ctx->{__stash}{entries},  $ctx->{__stash}{calendar_day},
            $ctx->{current_timestamp}, $ctx->{current_timestamp_end}
        );
        local $ctx->{__stash}{calendar_cell} = $day;
        unless ($is_padding) {
            $this_day = $prefix . sprintf( "%02d", $day - $pad_start );
            my $no_loop = 0;
            if (@left) {
                if ( substr( $left[0]->authored_on, 0, 8 ) eq $this_day ) {
                    @entries = @left;
                    @left    = ();
                }
                else {
                    $no_loop = 1;
                }
            }
            unless ( $no_loop || $iter_drained ) {
                while ( my $entry = $iter->() ) {
                    next unless !$cat || $entry->is_in_category($cat);
                    my $e_day = substr $entry->authored_on, 0, 8;
                    push( @left, $entry ), last
                        unless $e_day eq $this_day;
                    push @entries, $entry;
                }
                $iter_drained++ unless @left;
            }
            $ctx->{__stash}{entries}      = \@entries;
            $ctx->{current_timestamp}     = $this_day . '000000';
            $ctx->{current_timestamp_end} = $this_day . '235959';
            $ctx->{__stash}{calendar_day} = $day - $pad_start;
        }
        defined(
            my $out = $builder->build(
                $ctx, $tokens,
                {   %$cond,
                    CalendarWeekHeader  => ( $day - 1 ) % 7 == 0,
                    CalendarWeekFooter  => $day % 7 == 0,
                    CalendarIfEntries   => !$is_padding && scalar @entries,
                    CalendarIfNoEntries => !$is_padding
                        && !( scalar @entries ),
                    CalendarIfToday => ( $today eq $this_day ),
                    CalendarIfBlank => $is_padding,
                }
            )
        ) or return $ctx->error( $builder->errstr );
        $res .= $out;
    }
    $calendar_cache->{ $blog_id . ":" . $first . $prefix . $cat_name }
        = { output => $res, 'uc' => $uncompiled };
    return $res;
}

1;
