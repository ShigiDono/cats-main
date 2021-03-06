package CATS::UI::ProblemsRetest;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(url_f);
use CATS::Problem::Utils;
use CATS::RankTable;
use CATS::Request;
use CATS::Verdicts;

sub problems_mass_retest {
    my ($p) = @_;
    my @retest_pids = @{$p->{problem_id}} or return msg(1012);
    my %ignore_states;
    for (@{$p->{ignore_states}}) {
        my $st = $CATS::Verdicts::name_to_state->{$_ // ''};
        $ignore_states{$st} = 1 if defined $st;
    }
    my $count = 0;
    for my $retest_pid (@retest_pids) {
        my $runs = $dbh->selectall_arrayref(q~
            SELECT id, account_id, state FROM reqs
            WHERE contest_id = ? AND problem_id = ? ORDER BY id DESC~,
            { Slice => {} },
            $cid, $retest_pid
        );
        my %accounts;
        for (@$runs) {
            next if !$p->{all_runs} && $accounts{$_->{account_id}}++;
            next if $ignore_states{$_->{state} // 0};
            my $fields = {
                state => $cats::st_not_processed, judge_id => undef, points => undef, testsets => undef };
            CATS::Request::enforce_state($_->{id}, $fields) and ++$count;
        }
        $dbh->commit;
    }
    msg(1128, $count);
}

sub problems_recalc_points {
    my ($p) = @_;
    @{$p->{problem_id}} or return msg(1012);
    $dbh->do(_u $sql->update(
        reqs => { points => undef }, { contest_id => $cid, problem_id => $p->{problem_id} }
    ));
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}

my $retest_default_ignore = { IS => 1, SV => 1 };

sub problems_retest_frame {
    my ($p) = @_;
    $is_jury && !$contest->is_practice or return;
    my $lv = CATS::ListView->new(
        name => 'problems_retest', array_name => 'problems', template => 'problems_retest.html.tt');

    problems_mass_retest($p) if $p->{mass_retest};
    problems_recalc_points($p) if $p->{recalc_points};

    my @cols = (
        { caption => res_str(602), order_by => 'code', width => '30%' },
        { caption => res_str(639), order_by => 'in_queue', width => '10%' },
        { caption => res_str(622), order_by => 'status', width => '10%' },
        { caption => res_str(605), order_by => 'testsets', width => '10%' },
        { caption => res_str(604), order_by => 'accepted_count', width => '10%' },
    );
    $lv->define_columns(url_f('problems_retest'), 0, 0, [ @cols ]);
    CATS::Problem::Utils::define_common_searches($lv);
    $lv->define_db_searches([ qw(
        CP.code CP.testsets CP.points_testsets CP.status
    ) ]);

    my $psn = CATS::Problem::Utils::problem_status_names_enum($lv);

    my $reqs_count_sql = q~
        SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.contest_id = CP.contest_id AND D.state =~;
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            CP.code, P.title AS problem_name, CP.testsets, CP.points_testsets, CP.status,
            ($reqs_count_sql $cats::st_accepted) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded) AS time_limit_count,
            (SELECT COUNT(*) FROM reqs R
                WHERE R.contest_id = CP.contest_id AND R.problem_id = CP.problem_id AND
                R.state < $cats::request_processed) AS in_queue
        FROM problems P INNER JOIN contest_problems CP ON CP.problem_id = P.id
        WHERE CP.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $total_queue = 0;
    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        $total_queue += $c->{in_queue};
        return (
            status => $psn->{$c->{status}},
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            problem_id => $c->{pid},
            code => $c->{code},
            problem_name => $c->{problem_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            in_queue => $c->{in_queue},
            href_select_testsets => url_f('problem_select_testsets', pid => $c->{pid}, from_problems => 1),
        );
    };
    $lv->attach(url_f('problems_retest'), $fetch_record, $sth);

    $sth->finish;

    $t->param(
        total_queue => $total_queue,
        verdicts => [ map +{ short => $_->[0], checked => $retest_default_ignore->{$_->[0]} },
            @$CATS::Verdicts::name_to_state_sorted ],
    );
}
1;
