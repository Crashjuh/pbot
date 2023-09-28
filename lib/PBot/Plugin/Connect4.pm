# File: Connect4.pm
#
# Purpose: Connect-4 game for IRC. Includes options to resize board
# dimensions and how many pieces to connect.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Connect4;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::Duration qw/concise duration/;
use List::Util qw[min max];

use Data::Dumper;
$Data::Dumper::Useqq    = 1;
$Data::Dumper::Sortkeys = 1;

# This plugin was contributed by mannito, based on an earlier version of Battleship.pm

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->add(
        name   => 'connect4',
        help   => 'Connect-4 board game',
        subref => sub { $self->cmd_connect4(@_) },
    );

    $self->{pbot}->{event_dispatcher}->register_handler('irc.part', sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit', sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });

    $self->{channel} = $self->{pbot}->{registry}->get_value('connect4', 'channel') // '##connect4';
    $self->{debug}   = $self->{pbot}->{registry}->get_value('connect4', 'debug')   // 0;
    $self->create_states;
}

sub unload($self) {
    $self->{pbot}->{commands}->remove('connect4');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.quit');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
    $self->{pbot}->{event_queue}->dequeue_event('connect4 loop');
}

sub on_kick($self, $event_type, $event) {
    my ($nick, $user, $host)  = ($event->nick, $event->user, $event->host);
    my ($victim, $reason) = ($event->to, $event->{args}[1]);
    my $channel = $event->{args}[0];
    return 0 if lc $channel ne $self->{channel};
    $self->player_left($nick, $user, $host);
    return 0;
}

sub on_departure($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);
    my $type = uc $event->type;
    return 0 if $type ne 'QUIT' and lc $channel ne $self->{channel};
    $self->player_left($nick, $user, $host);
    return 0;
}

my %color = (
    white      => "\x0300",
    black      => "\x0301",
    blue       => "\x0302",
    green      => "\x0303",
    red        => "\x0304",
    maroon     => "\x0305",
    purple     => "\x0306",
    orange     => "\x0307",
    yellow     => "\x0308",
    lightgreen => "\x0309",
    teal       => "\x0310",
    cyan       => "\x0311",
    lightblue  => "\x0312",
    magneta    => "\x0313",
    gray       => "\x0314",
    lightgray  => "\x0315",

    bold      => "\x02",
    italics   => "\x1D",
    underline => "\x1F",
    reverse   => "\x16",

    reset => "\x0F",
);

my $DEFAULT_NX          = 7;
my $DEFAULT_NY          = 6;
my $DEFAULT_CONNECTIONS = 4;
my $MAX_NX              = 80;
my $MAX_NY              = 12;

# challenge options: CONNS:ROWSxCOLS
sub parse_challenge($self, $options) {
    my ($conns, $xy, $nx, $ny);

    "x" =~ /x/;    # clear $1, $2 ...
    if ($options !~ m/^(\d+)(:(\d+)x(\d+))?$/) { return "Invalid options '$options', use: <CONNS:ROWSxCOLS>"; }

    $conns = $1;
    $xy    = $2;
    $ny    = $3;
    $nx    = $4;

    $self->{N_X}         = (not length $nx)    ? $DEFAULT_NX          : $nx;
    $self->{N_Y}         = (not length $ny)    ? $DEFAULT_NY          : $ny;
    $self->{CONNECTIONS} = (not length $conns) ? $DEFAULT_CONNECTIONS : $conns;

    # auto adjust board size for `challenge N'
    if ((not length $xy) && ($self->{CONNECTIONS} >= $self->{N_X} || $self->{CONNECTIONS} >= $self->{N_Y})) {
        $self->{N_X} = min($self->{CONNECTIONS} * 2 - 1, $MAX_NX);
        $self->{N_Y} = min($self->{CONNECTIONS} * 2 - 2, $MAX_NY);
    }

    if ($self->{N_X} > $MAX_NX || $self->{N_Y} > $MAX_NY) {
        return "Invalid board options '$self->{CONNECTIONS}:$self->{N_Y}x$self->{N_X}', " . "maximum board size is: ${MAX_NY}x${MAX_NX}.";
    }

    if ($self->{N_X} < $self->{CONNECTIONS} && $self->{N_Y} < $self->{CONNECTIONS}) {
        return "Invalid board options '$self->{CONNECTIONS}:$self->{N_Y}x$self->{N_X}', " . "rows or columns must be >= than connections.";
    }

    return 0;
}

sub cmd_connect4($self, $context) {
    $context->{arguments} =~ s/^\s+|\s+$//g;

    my $usage = "Usage: connect4 challenge|accept|play|board|quit|players|kick|abort; for more information about a command: connect4 help <command>";

    my ($command, $arguments, $options) = split / /, $context->{arguments}, 3;

    if (defined $command) {
        $command = lc $command;
    } else {
        $command = '';
    }

    given ($command) {
        when ('help') {
            given ($arguments) {
                when ('help') { return "Seriously?"; }

                when ('challenge') { return "challenge [nick] [connections[:ROWSxCOLS]] -- connections has to be <= than rows or columns (duh!)."; }

                default {
                    if   (length $arguments) { return "connect4 has no such command '$arguments'. I can't help you with that."; }
                    else                     { return "Usage: connect4 help <command>"; }
                }
            }
        }

        when ('challenge') {
            if ($self->{current_state} ne 'nogame') { return "There is already a game of connect4 underway."; }

            $self->{N_X}         = $DEFAULT_NX;
            $self->{N_Y}         = $DEFAULT_NY;
            $self->{CONNECTIONS} = $DEFAULT_CONNECTIONS;

            my $err;

            if ((not length $arguments) || ($arguments =~ m/^\d+.*$/ && not($err = $self->parse_challenge($arguments)))) {
                $self->{current_state} = 'accept';
                $self->{state_data}    = {players => [], counter => 0};

                $self->{pbot}->{event_queue}->enqueue_event(
                    sub {
                        $self->run_one_state;
                    }, 1, 'connect4 loop', 1
                );

                my $id     = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
                my $player = {id => $id, name => $context->{nick}, missedinputs => 0};
                push @{$self->{state_data}->{players}}, $player;

                $player = {id => -1, name => undef, missedinputs => 0};
                push @{$self->{state_data}->{players}}, $player;
                return "/msg $self->{channel} $context->{nick} has made an open challenge (Connect-$self->{CONNECTIONS} @ "
                  . "$self->{N_Y}x$self->{N_X} board)! Use `accept` to accept their challenge.";
            }

            if ($err) { return $err; }

            my $challengee = $self->{pbot}->{nicklist}->is_present($self->{channel}, $arguments);

            if (not $challengee) { return "That nick is not present in this channel. Invite them to $self->{channel} and try again!"; }

            if (length $options) {
                if ($err = $self->parse_challenge($options)) { return $err; }
            }

            $self->{current_state} = 'accept';
            $self->{state_data}    = {players => [], counter => 0};

            $self->{pbot}->{event_queue}->enqueue_event(
                sub {
                    $self->run_one_state;
                }, 1, 'connect4 loop', 1
            );

            my $id     = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            my $player = {id => $id, name => $context->{nick}, missedinputs => 0};
            push @{$self->{state_data}->{players}}, $player;

            ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($challengee);
            $player = {id => $id, name => $challengee, missedinputs => 0};
            push @{$self->{state_data}->{players}}, $player;

            return "/msg $self->{channel} $context->{nick} has challenged $challengee to "
              . "Connect-$self->{CONNECTIONS} @ $self->{N_Y}x$self->{N_X} board! Use `accept` to accept their challenge.";
        }

        when ('accept') {
            if ($self->{current_state} ne 'accept') { return "/msg $context->{nick} This is not the time to use `accept`."; }

            my $id     = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            my $player = $self->{state_data}->{players}->[1];

            # open challenge
            if ($player->{id} == -1) {
                $player->{id}   = $id;
                $player->{name} = $context->{nick};
            }

            if ($player->{id} == $id) {
                $player->{accepted} = 1;
                return "/msg $self->{channel} $context->{nick} has accepted $self->{state_data}->{players}->[0]->{name}'s challenge!";
            } else {
                return "/msg $context->{nick} You have not been challenged to a game of Connect4 yet.";
            }
        }

        when ($_ eq 'decline' or $_ eq 'quit' or $_ eq 'forfeit' or $_ eq 'concede') {
            my $id      = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    splice @{$self->{state_data}->{players}}, $i--, 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) { $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1 }
                return "/msg $self->{channel} $context->{nick} has left the game!";
            } else {
                return "$context->{nick}: But you are not even playing the game.";
            }
        }

        when ('abort') {
            if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask})) {
                return "$context->{nick}: Only admins may abort the game.";
            }

            $self->{current_state} = 'gameover';
            return "/msg $self->{channel} $context->{nick}: The game has been aborted.";
        }

        when ('players') {
            if    ($self->{current_state} eq 'accept')     { return "$self->{state_data}->{players}->[0]->{name} has challenged $self->{state_data}->{players}->[1]->{name}!"; }
            elsif (@{$self->{state_data}->{players}} == 2) { return "$self->{state_data}->{players}->[0]->{name} is playing with $self->{state_data}->{players}->[1]->{name}!"; }
            else                                           { return "There are no players playing right now. Start a game with `connect4 challenge <nick>`!"; }
        }

        when ('kick') {
            if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask})) {
                return "$context->{nick}: Only admins may kick people from the game.";
            }

            if (not length $arguments) { return "Usage: connect4 kick <nick>"; }

            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if (lc $self->{state_data}->{players}->[$i]->{name} eq $arguments) {
                    splice @{$self->{state_data}->{players}}, $i--, 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) { $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1 }
                return "/msg $self->{channel} $context->{nick}: $arguments has been kicked from the game.";
            } else {
                return "$context->{nick}: $arguments isn't even in the game.";
            }
        }

        when ('play') {
            if ($self->{debug}) { $self->{pbot}->{logger}->log("Connect4: play state: $self->{current_state}\n" . Dumper $self->{state_data}); }

            if ($self->{current_state} ne 'playermove') { return "$context->{nick}: It's not time to do that now."; }

            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            my $player;

            if    ($self->{state_data}->{players}->[0]->{id} == $id) { $player = 0; }
            elsif ($self->{state_data}->{players}->[1]->{id} == $id) { $player = 1; }
            else                                                     { return "You are not playing in this game."; }

            if ($self->{state_data}->{current_player} != $player) { return "$context->{nick}: It is not your turn to attack!"; }

            if ($self->{player}->[$player]->{done}) { return "$context->{nick}: You have already played this turn."; }

            if ($arguments !~ m/^\d+$/) { return "$context->{nick}: Usage: connect4 play <location>; <location> must be in the [1, $self->{N_X}] range."; }

            if ($self->play($player, uc $arguments)) {
                if ($self->{player}->[$player]->{won}) {
                    $self->{previous_state} = $self->{current_state};
                    $self->{current_state}  = 'checkplayer';
                    $self->run_one_state;
                } else {
                    $self->{player}->[$player]->{done}    = 1;
                    $self->{player}->[!$player]->{done}   = 0;
                    $self->{state_data}->{current_player} = !$player;
                    $self->{state_data}->{ticks}          = 1;
                    $self->{state_data}->{first_tock}     = 1;
                    $self->{state_data}->{counter}        = 0;
                }
            }
            return "";
        }

        when ('board') {
            if ($self->{current_state} eq 'nogame' or $self->{current_state} eq 'accept' or $self->{current_state} eq 'genboard' or $self->{current_state} eq 'gameover') {
                return "$context->{nick}: There is no board to show right now.";
            }

            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            for (my $i = 0; $i < 2; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->send_message($self->{channel}, "$context->{nick} surveys the board!");
                    $self->show_board;
                    return "";
                }
            }

            $self->show_board;
        }

        default { return $usage; }
    }

    return "";
}

sub player_left($self, $nick, $user, $host) {
    my $id      = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    my $removed = 0;

    for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
            splice @{$self->{state_data}->{players}}, $i--, 1;
            $self->send_message($self->{channel}, "$nick has left the game!");
            $removed = 1;
        }
    }

    if ($removed) {
        if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) { $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1 }
        return "/msg $self->{channel} $nick has left the game!";
    }
}

sub send_message($self, $to, $text, $delay = 0) {
    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $message = {
        nick       => $botnick,
        user       => 'connect4',
        host       => 'localhost',
        hostmask   => "$botnick!connect4\@localhost",
        command    => 'connect4',
        checkflood => 1,
        message    => $text
    };
    $self->{pbot}->{interpreter}->add_message_to_output_queue($to, $message, $delay);
}

sub run_one_state($self) {
    # check for naughty or missing players
    if ($self->{current_state} =~ /(?:move|accept)/) {
        my $removed = 0;
        for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
            if ($self->{state_data}->{players}->[$i]->{missedinputs} >= 3) {
                $self->send_message(
                    $self->{channel},
                    "$color{red}$self->{state_data}->{players}->[$i]->{name} has missed too many prompts and has been ejected from the game!$color{reset}"
                );
                splice @{$self->{state_data}->{players}}, $i--, 1;
                $removed = 1;
            }
        }

        if ($removed) {
            if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) { $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1 }
        }

        if (not @{$self->{state_data}->{players}} == 2) {
            $self->send_message($self->{channel}, "A player has left the game! The game is now over.");
            $self->{current_state} = 'nogame';
        }
    }

    my $state_data = $self->{state_data};

    # this shouldn't happen
    if (not defined $self->{current_state}) {
        $self->{pbot}->{logger}->log("Connect4 state broke.\n");
        $self->{current_state} = 'nogame';
        return;
    }

    # transistioned to a brand new state; prepare first tock
    if ($self->{previous_state} ne $self->{current_state}) {
        $state_data->{newstate} = 1;
        $state_data->{ticks}    = 1;

        if (exists $state_data->{tick_drift}) {
            $state_data->{ticks} += $state_data->{tick_drift};
            delete $state_data->{tick_drift};
        }

        $state_data->{first_tock} = 1;
        $state_data->{counter}    = 0;
    } else {
        $state_data->{newstate} = 0;
    }

    # dump new state data for logging/debugging
    if ($self->{debug} and $state_data->{newstate}) { $self->{pbot}->{logger}->log("Connect4: New state: $self->{current_state}\n" . Dumper $state_data); }

    # run one state/tick
    $state_data = $self->{states}{$self->{current_state}}{sub}($state_data);

    if ($state_data->{tocked}) {
        delete $state_data->{tocked};
        delete $state_data->{first_tock};
        $state_data->{ticks} = 0;
    }

    # transform to next state
    $state_data->{previous_result} = $state_data->{result};
    $self->{previous_state}        = $self->{current_state};
    $self->{current_state}         = $self->{states}{$self->{current_state}}{trans}{$state_data->{result}};
    $self->{state_data}            = $state_data;

    # next tick
    $self->{state_data}->{ticks}++;
}

sub create_states($self) {
    $self->{pbot}->{logger}->log("Connect4: Creating game state machine\n");

    $self->{previous_state} = '';
    $self->{current_state}  = 'nogame';
    $self->{state_data}     = {players => [], ticks => 0, newstate => 1};

    $self->{state_data}->{current_player} = 0;

    $self->{states}{'nogame'}{sub}              = sub { $self->nogame(@_) };
    $self->{states}{'nogame'}{trans}{challenge} = 'accept';
    $self->{states}{'nogame'}{trans}{nogame}    = 'nogame';

    $self->{states}{'accept'}{sub}           = sub { $self->accept(@_) };
    $self->{states}{'accept'}{trans}{stop}   = 'nogame';
    $self->{states}{'accept'}{trans}{wait}   = 'accept';
    $self->{states}{'accept'}{trans}{accept} = 'genboard';

    $self->{states}{'genboard'}{sub} = sub { $self->genboard(@_) };
    $self->{states}{'genboard'}{trans}{next} = 'showboard';

    $self->{states}{'showboard'}{sub} = sub { $self->showboard(@_) };
    $self->{states}{'showboard'}{trans}{next} = 'playermove';

    $self->{states}{'playermove'}{sub}         = sub { $self->playermove(@_) };
    $self->{states}{'playermove'}{trans}{wait} = 'playermove';
    $self->{states}{'playermove'}{trans}{next} = 'checkplayer';

    $self->{states}{'checkplayer'}{sub}         = sub { $self->checkplayer(@_) };
    $self->{states}{'checkplayer'}{trans}{end}  = 'gameover';
    $self->{states}{'checkplayer'}{trans}{next} = 'playermove';

    $self->{states}{'gameover'}{sub}         = sub { $self->gameover(@_) };
    $self->{states}{'gameover'}{trans}{wait} = 'gameover';
    $self->{states}{'gameover'}{trans}{next} = 'nogame';
}

# connect4 stuff

sub init_game($self, $nick1, $nick2) {
    $self->{chips} = 0;
    $self->{draw}  = 0;

    $self->{board}       = [];
    $self->{winner_line} = [];

    $self->{player} = [
        {nick => $nick1, done => 0},
        {nick => $nick2, done => 0}
    ];

    $self->{turn}  = 0;
    $self->{horiz} = 0;

    $self->generate_board;
}

sub generate_board($self) {
    my ($x, $y);

    for ($y = 0; $y < $self->{N_Y}; $y++) {
        for ($x = 0; $x < $self->{N_X}; $x++) { $self->{board}->[$y][$x] = ' '; }
    }
}

sub check_one($self, $y, $x, $prev) {
    my $chip = $self->{board}[$y][$x];

    push @{$self->{winner_line}}, "$y $x";

    if ($chip eq ' ' || $chip ne $prev) { $self->{winner_line} = ($chip eq ' ') ? [] : ["$y $x"]; }

    return (scalar @{$self->{winner_line}} == $self->{CONNECTIONS}, $chip);
}

sub connected($self) {
    my ($i, $j, $row, $col, $prev) = (0, 0, 0, 0, 0);
    my $rv;

    for ($row = 0; $row < $self->{N_Y}; $row++) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($i = $row, $j = $self->{N_X} - 1; $i < $self->{N_Y} && $j >= 0; $i++, $j--) {
            ($rv, $prev) = $self->check_one($i, $j, $prev);
            if ($rv) { return 1; }
        }
    }

    for ($col = $self->{N_X} - 1; $col >= 0; $col--) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($i = 0, $j = $col; $i < $self->{N_Y} && $j >= 0; $i++, $j--) {
            ($rv, $prev) = $self->check_one($i, $j, $prev);
            if ($rv) { return 2; }
        }
    }

    for ($row = 0; $row < $self->{N_Y}; $row++) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($i = $row, $j = 0; $i < $self->{N_Y}; $i++, $j++) {
            ($rv, $prev) = $self->check_one($i, $j, $prev);
            if ($rv) { return 3; }
        }
    }

    for ($col = 0; $col < $self->{N_X}; $col++) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($i = 0, $j = $col; $i < $self->{N_Y} && $j < $self->{N_X}; $i++, $j++) {
            ($rv, $prev) = $self->check_one($i, $j, $prev);
            if ($rv) { return 4; }
        }
    }

    for ($row = 0; $row < $self->{N_Y}; $row++) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($col = 0; $col < $self->{N_X}; $col++) {
            ($rv, $prev) = $self->check_one($row, $col, $prev);
            if ($rv) { return 5; }
        }
    }

    for ($col = 0; $col < $self->{N_X}; $col++) {
        $prev = ' ';
        $self->{winner_line} = [];
        for ($row = $self->{N_Y} - 1; $row >= 0; $row--) {
            ($rv, $prev) = $self->check_one($row, $col, $prev);
            if ($rv) { return 6; }
        }
    }

    $self->{winner_line} = [];
    return 0;
}

sub column_top($self, $x) {
    my $y;

    for ($y = 0; $y < $self->{N_Y}; $y++) {
        if ($self->{board}->[$y][$x] ne ' ') { return $y - 1; }
    }
    return -1;    # shouldnt happen
}

sub play($self, $player, $location) {
    my ($draw, $c4, $x, $y);

    $x = $location - 1;

    $self->{pbot}->{logger}->log("play player $player: $x\n");

    if ($x < 0 || $x >= $self->{N_X} || $self->{board}[0][$x] ne ' ') {
        $self->send_message($self->{channel}, "Target illegal/out of range, try again.");
        return 0;
    }

    $y = $self->column_top($x);

    $self->{board}->[$y][$x] = $player ? 'O' : 'X';
    $self->{chips}++;

    $c4   = $self->connected;
    $draw = $self->{chips} == $self->{N_X} * $self->{N_Y};

    my $nick1 = $self->{player}->[$player]->{nick};
    my $nick2 = $self->{player}->[$player ? 0 : 1]->{nick};

    $self->send_message($self->{channel}, "$nick1 placed piece at column: $location");

    if ($c4) {
        $self->send_message($self->{channel}, "$nick1 connected $self->{CONNECTIONS} pieces! $color{red}--- VICTORY! --- $color{reset}");
        $self->{player}->[$player]->{won} = 1;
    } elsif ($draw) {
        $self->send_message($self->{channel}, "$color{red}--- DRAW! --- $color{reset}");
        $self->{draw} = 1;
    }

    return 1;
}

sub show_board($self) {
    my ($x, $y, $buf, $chip, $c);

    $self->{pbot}->{logger}->log("showing board\n");

    my $nick1 = $self->{player}->[0]->{nick};
    my $nick2 = $self->{player}->[1]->{nick};

    $buf = sprintf("%s: %s ", $nick1, "$color{yellow}X$color{reset}");
    $buf .= sprintf("%s: %s\n", $nick2, "$color{red}O$color{reset}");

    $buf .= "$color{bold}";

    for ($x = 1; $x < $self->{N_X} + 1; $x++) {
        if ($x % 10 == 0) {
            $buf .= $color{yellow};
            $buf .= ' ';
            $buf .= $x % 10;
            $buf .= ' ';
            $buf .= $color{reset} . $color{bold};
        } else {
            $buf .= " " . $x % 10 . " ";
        }
    }

    $buf .= "\n";

    for ($y = 0; $y < $self->{N_Y}; $y++) {
        for ($x = 0; $x < $self->{N_X}; $x++) {
            $chip = $self->{board}->[$y][$x];

            my $rc = "$y $x";

            $c = $chip eq 'O' ? $color{red} : $color{yellow};

            if (grep(/^$rc$/, @{$self->{winner_line}})) { $c .= $color{bold}; }

            $buf .= $color{blue} . "[";
            $buf .= $c . $chip . $color{reset};
            $buf .= $color{blue} . "]";
        }

        $buf .= $color{reset};
        $buf .= "\n";
    }

    foreach my $line (split /\n/, $buf) { $self->send_message($self->{channel}, $line); }
}

# state subroutines

sub nogame($self, $state) {
    $state->{result} = 'nogame';
    $self->{pbot}->{event_queue}->update_repeating('connect4 loop', 0);
    return $state;
}

sub accept($self, $state) {
    $state->{max_count} = 3;

    if ($state->{players}->[1]->{accepted}) {
        $state->{result} = 'accept';
        return $state;
    }

    my $tock = 15;

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{counter} > $state->{max_count}) {
            if ($state->{players}->[1]->{id} == -1) { $self->send_message($self->{channel}, "Nobody has accepted $state->{players}->[0]->{name}'s challenge."); }
            else { $self->send_message($self->{channel}, "$state->{players}->[1]->{name} has failed to accept $state->{players}->[0]->{name}'s challenge."); }
            $state->{result}  = 'stop';
            $state->{players} = [];
            return $state;
        }

        if ($state->{players}->[1]->{id} == -1) {
            $self->send_message($self->{channel}, "$state->{players}->[0]->{name} has made an open challenge! Use `accept` to accept their challenge.");
        } else {
            $self->send_message($self->{channel}, "$state->{players}->[1]->{name}: $state->{players}->[0]->{name} has challenged you! Use `accept` to accept their challenge.");
        }
    }

    $state->{result} = 'wait';
    return $state;
}

sub genboard($self, $state) {
    $self->init_game($state->{players}->[0]->{name}, $state->{players}->[1]->{name});
    $state->{max_count} = 3;
    $state->{result} = 'next';
    return $state;
}

sub showboard($self, $state) {
    $self->send_message($self->{channel}, "Showing board ...");
    $self->show_board;
    $self->send_message($self->{channel}, "Fight! Anybody (players and spectators) can use `board` at any time to see latest version of the board!");
    $state->{result} = 'next';
    return $state;
}

sub playermove($self, $state) {
    my $tock;

    if ($state->{first_tock}) {
        $tock = 3;
    } else {
        $tock = 15;
    }

    if ($self->{player}->[$state->{current_player}]->{done}) {
        $self->{pbot}->{logger}->log("playermove: player $state->{current_player} done, nexting\n");
        $state->{result} = 'next';
        return $state;
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;
        if (++$state->{counter} > $state->{max_count}) {
            $state->{players}->[$state->{current_player}]->{missedinputs}++;
            $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name} failed to play in time. They forfeit their turn!");
            $self->{player}->[$state->{current_player}]->{done}  = 1;
            $self->{player}->[!$state->{current_player}]->{done} = 0;
            $state->{current_player} = !$state->{current_player};
            $state->{result} = 'next';
            return $state;
        }

        my $red = $state->{counter} == $state->{max_count} ? $color{red} : '';

        my $remaining = 15 * $state->{max_count};
        $remaining -= 15 * ($state->{counter} - 1);
        $remaining = "(" . (concise duration $remaining) . " remaining)";

        $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name}: $red$remaining Play now via `play <location>`!$color{reset}");
    }

    $state->{result} = 'wait';
    return $state;
}

sub checkplayer($self, $state) {
    if   ($self->{player}->[$state->{current_player}]->{won} || $self->{draw}) {
        $state->{result} = 'end';
    } else {
        $state->{result} = 'next';
    }
    return $state;
}

sub gameover($self, $state) {
    if ($state->{ticks} % 2 == 0) {
        $self->show_board;
        $self->send_message($self->{channel}, "Game over!");
        $state->{players} = [];
        $state->{counter} = 0;
        $state->{result}  = 'next';
    } else {
        $state->{result} = 'wait';
    }
    return $state;
}

1;
