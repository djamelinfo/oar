# $Id$
package Gantt_hole_storage;
require Exporter;
use oar_resource_tree;
use Data::Dumper;
use warnings;
use strict;

# Note : All dates are in seconds
# Resources are integer so we store them in bit vectors
# Warning : this gantt cannot manage overlaping time slots

# 2^32 is infinity in 32 bits stored time
my $Infinity = 4294967296;

# Prototypes
# gantt chart management
sub new($$);
sub new_with_1_hole($$$$$);
sub add_new_resources($$);
sub set_occupation($$$$);
sub get_free_resources($$$);
sub find_first_hole($$$$$);
sub pretty_print($);
sub get_infinity_value();

###############################################################################

sub get_infinity_value(){
    return($Infinity);
}

sub pretty_print($){
    my $gantt = shift;
   
    my @bits = split(//, unpack("b*", $gantt->[0]->[2]));
    print("@bits\n");
    foreach my $g (@{$gantt}){
        print("BEGIN : $g->[0]\n");
        foreach my $h (@{$g->[1]}){
            @bits = split(//, unpack("b*", $h->[1]));
            print("    $h->[0] : @bits\n");
        }
        print("\n");
    }
}

# Creates an empty Gantt
# arg : number of the max resource id
sub new($$){
    my $max_resource_number = shift;
    my $minimum_hole_duration = shift;

    $minimum_hole_duration = 0 if (!defined($minimum_hole_duration));

    my $empty_vec = '';
    vec($empty_vec, $max_resource_number, 1) = 0;
    
    my $result =[
                    [
                        0,                              # start time of this hole
                        [                               # ref of a structure which contains hole stop times and corresponding resources (ordered by end time)
                            [$Infinity, $empty_vec]
                        ],
                        $empty_vec,                     # Store all inserted resources (Only for the first Gantt hole)
                        $empty_vec,                     # Store empty vec with enough 0 (Only for the first hole)
                        $minimum_hole_duration,         # minimum time for a hole
                        [$Infinity,$Infinity]           # times that find_first_hole must not go after
                    ]
                ];
    
    return($result);
}


# Creates a Gantt with 1 hole
# arg : number of the max resource id
sub new_with_1_hole($$$$$){
    my $max_resource_number = shift;
    my $minimum_hole_duration = shift;
    my $date = shift;
    my $duration = shift;
    my $resources_vec = shift;

    my $gantt = Gantt_hole_storage::new($max_resource_number, $minimum_hole_duration);

    # Feed vector with enough 0
    $resources_vec |= $gantt->[0]->[3];

    $gantt->[0]->[0] = $date;
    $gantt->[0]->[1] = [[($date + $duration), $resources_vec]];

    return($gantt);
}


# Adds and initializes new resources in the gantt
# args : gantt ref, bit vector of resources
sub add_new_resources($$) {
    my ($gantt, $resources_vec) = @_;

    # Feed vector with enough 0
    $resources_vec |= $gantt->[0]->[3]; 
    
    # Verify which resources are not already inserted
    my $resources_to_add_vec = $resources_vec & (~ $gantt->[0]->[2]);
   
    if (unpack("%32b*",$resources_to_add_vec) > 0){
        # We need to insert new resources on all hole
        my $g = 0;
        while ($g <= $#{$gantt}){
            # Add resources
            if ($gantt->[$g]->[1]->[$#{$gantt->[$g]->[1]}]->[0] == $Infinity){
                $gantt->[$g]->[1]->[$#{$gantt->[$g]->[1]}]->[1] |= $resources_to_add_vec;
            }else{
                push(@{$gantt->[$g]->[1]}, [$Infinity, $resources_vec]);
            }
            $g++;
        }
        # Keep already inserted resources in mind
        $gantt->[0]->[2] |= $resources_vec;
    }
}


# Inserts in the gantt new resource occupations
# args : gantt ref, start slot date, slot duration, resources bit vector
sub set_occupation($$$$){
    my ($gantt, $date, $duration, $resources_vec) = @_;

    # Feed vector with enough 0
    $resources_vec |= $gantt->[0]->[3];

    # If a resource was not initialized
    add_new_resources($gantt,$resources_vec); # If it is not yet done

    my $new_hole = [
                        $date + $duration + 1,
                        []
                    ];
    
    my $g = 0;
    while (($g <= $#{$gantt}) and ($gantt->[$g]->[0] <= $new_hole->[0])){
        my $slot_deleted = 0;
        # Look at all holes that are before the end of the occupation
        if (($#{$gantt->[$g]->[1]} >= 0) and ($gantt->[$g]->[1]->[$#{$gantt->[$g]->[1]}]->[0] >= $date)){
            # Look at holes with a biggest slot >= $date
            my $h = 0;
            my $slot_date_here = 0;
            while ($h <= $#{$gantt->[$g]->[1]}){
                # Look at all slots
                $slot_date_here = 1 if ($gantt->[$g]->[1]->[$h]->[0] == $date);
                if ($gantt->[$g]->[1]->[$h]->[0] > $date){
                    # This slot ends after $date
                    #print($date - $gantt->[$g]->[0]." -- $gantt->[0]->[4]\n");
                    if (($gantt->[$g]->[0] < $date) and ($slot_date_here == 0) and ($date - $gantt->[$g]->[0] > $gantt->[0]->[4])){
                        # We must create a smaller slot (hole start time < $date)
                        splice(@{$gantt->[$g]->[1]}, $h, 0, [ $date , $gantt->[$g]->[1]->[$h]->[1] ]);
                        $h++;   # Go to the slot that we were on it before the splice
                        $slot_date_here = 1;
                    }
                    # Add new slots in the new hole
                    if (($new_hole->[0] < $gantt->[$g]->[1]->[$h]->[0]) and ($gantt->[$g]->[1]->[$h]->[0] - $new_hole->[0] > $gantt->[0]->[4])){
                        # copy slot in the new hole if needed
                        my $slot = 0;
                        while (($slot <= $#{$new_hole->[1]}) and ($new_hole->[1]->[$slot]->[0] < $gantt->[$g]->[1]->[$h]->[0])){
                            # Find right index in the sorted slot array
                            $slot++;
                        }
                        if ($slot <= $#{$new_hole->[1]}){
                            if ($new_hole->[1]->[$slot]->[0] == $gantt->[$g]->[1]->[$h]->[0]){
                                # If the slot already exists
                                $new_hole->[1]->[$slot]->[1] |= $gantt->[$g]->[1]->[$h]->[1];
                            }else{
                                # Insert the new slot
                                splice(@{$new_hole->[1]}, $slot, 0, [$gantt->[$g]->[1]->[$h]->[0], $gantt->[$g]->[1]->[$h]->[1]]);
                            }
                        }elsif ($new_hole->[0] < $gantt->[$g]->[1]->[$h]->[0]){
                            # There is no slot so we create one
                            push(@{$new_hole->[1]}, [ $gantt->[$g]->[1]->[$h]->[0], $gantt->[$g]->[1]->[$h]->[1] ]);
                        }
                    }
                    # Remove new occupied resources from the current slot
                    $gantt->[$g]->[1]->[$h]->[1] &= (~ $resources_vec) ;
                    if (unpack("%32b*",$gantt->[$g]->[1]->[$h]->[1]) == 0){
                        # There is no free resource on this slot so we delete it
                        splice(@{$gantt->[$g]->[1]}, $h, 1);
                        $h--;
                        $slot_deleted = 1;
                    }
                }
                # Go to the next slot
                $h++;
            }
        }
        if (($slot_deleted == 1) and ($#{$gantt->[$g]->[1]} < 0)){
            # There is no free slot on the current hole so we delete it
            splice(@{$gantt}, $g, 1);
            $g--;
        }
        # Go to the next hole
        $g++;
    }
    if ($#{$new_hole->[1]} >= 0){
        # Add the new hole
        if (($g > 0) and ($g - 1 <= $#{$gantt}) and ($gantt->[$g - 1]->[0] == $new_hole->[0])){
            # Verify if the hole does not already exist
            splice(@{$gantt}, $g - 1, 1, $new_hole);
        }else{
            splice(@{$gantt}, $g, 0, $new_hole);
        }
    }
}

# Find the first hole in the data structure that can fit the given slot
sub find_hole($$$){
    my ($gantt, $begin_date, $duration) = @_;

    my $end_date = $begin_date + $duration;
    my $g = 0;
    while (($g <= $#{$gantt}) and ($gantt->[$g]->[0] < $begin_date) and ($gantt->[$g]->[1]->[$#{$gantt->[$g]->[1]}]->[0] < $end_date)){
        $g++
    }

    return($g);
}

# Returns the vector of the maximum free resources at the given date for the given duration
sub get_free_resources($$$){
    my ($gantt, $begin_date, $duration) = @_;
    
    my $end_date = $begin_date + $duration;
    my $hole_index = 0;
    # search the nearest hole
    while (($hole_index <= $#{$gantt}) and ($gantt->[$hole_index]->[0] < $begin_date) and
            (($gantt->[$hole_index]->[1]->[$#{$gantt->[$hole_index]->[1]}]->[0] < $end_date) or 
                (($hole_index + 1 <= $#{$gantt}) and $gantt->[$hole_index + 1]->[0] < $begin_date))){
        $hole_index++;
    }
    return($gantt->[0]->[4]) if ($hole_index > $#{$gantt});
    
    my $h = 0;
    while (($h <= $#{$gantt->[$hole_index]->[1]}) and ($gantt->[$hole_index]->[1]->[$h]->[0] < $end_date)){
        $h++;
    }
    return($gantt->[$hole_index]->[1]->[$h]->[1]);
}


# Take a list of resource trees and find a hole that fit
# args : gantt ref, initial time from which the search will begin, job duration, list of resource trees
sub find_first_hole($$$$$){
    my ($gantt, $initial_time, $duration, $tree_description_list, $timeout) = @_;

    # $tree_description_list->[0]  --> First resource group corresponding tree
    # $tree_description_list->[1]  --> Second resource group corresponding tree
    # ...

    return ($Infinity, ()) if (!defined($tree_description_list->[0]));

    my @result_tree_list = ();
    my $end_loop = 0;
    my $current_time = $initial_time;
    my $timeout_initial_time = time();
    # begin research at the first potential hole
    my $current_hole_index = find_hole($gantt, $initial_time, $duration);
    my $h = 0;
    while ($end_loop == 0){
        # Go to a right hole
        while (($current_hole_index <= $#{$gantt}) and
                (($gantt->[$current_hole_index]->[0] + $duration > $gantt->[$current_hole_index]->[1]->[$h]->[0]) or
                   (($initial_time > $gantt->[$current_hole_index]->[0]) and
                        ($initial_time + $duration > $gantt->[$current_hole_index]->[1]->[$h]->[0])))){
            while (($h <= $#{$gantt->[$current_hole_index]->[1]}) and
                    (($gantt->[$current_hole_index]->[0] + $duration > $gantt->[$current_hole_index]->[1]->[$h]->[0]) or
                        (($initial_time > $gantt->[$current_hole_index]->[0]) and
                        ($initial_time + $duration > $gantt->[$current_hole_index]->[1]->[$h]->[0])))){
                $h++;
            }
            if ($h > $#{$gantt->[$current_hole_index]->[1]}){
                # in this hole no slot fits so we must search in the next hole
                $h = 0;
                $current_hole_index++;
            }
        }
        if ($current_hole_index > $#{$gantt}){
            # no hole fits
            $current_time = $Infinity;
            @result_tree_list = ();
            $end_loop = 1;
        }else{
            #print("Treate hole $current_hole_index, $h : $gantt->[$current_hole_index]->[0] --> $gantt->[$current_hole_index]->[1]->[$h]->[0]\n");
            $current_time = $gantt->[$current_hole_index]->[0] if ($initial_time < $gantt->[$current_hole_index]->[0]);
            #Check all trees
            my $tree_clone;
            my $i = 0;
            do{
                # clone the tree, so we can work on it without damage
                $tree_clone = oar_resource_tree::clone($tree_description_list->[$i]);
                #Remove tree leafs that are not free
                foreach my $l (oar_resource_tree::get_tree_leafs($tree_clone)){
                    if (!vec($gantt->[$current_hole_index]->[1]->[$h]->[1],oar_resource_tree::get_current_resource_value($l),1)){
                        oar_resource_tree::delete_subtree($l);
                    }
                }
                #print(Dumper($tree_clone));
                $tree_clone = oar_resource_tree::delete_tree_nodes_with_not_enough_resources($tree_clone);
                
#$Data::Dumper::Purity = 0;
#$Data::Dumper::Terse = 0;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Deepcopy = 0;
#                print(Dumper($tree_clone));

                $result_tree_list[$i] = $tree_clone;
                $i ++;
            }while(defined($tree_clone) && ($i <= $#$tree_description_list));
            if (defined($tree_clone)){
                # We find the first hole
                $end_loop = 1;
            }else{
                # Go to the next slot of this hole
                if ($h >= $#{$gantt->[$current_hole_index]->[1]}){
                    $h = 0;
                    $current_hole_index++;
                }else{
                    $h++;
                }
            }
        }
        # Check timeout
        if (($current_hole_index <= $#{$gantt}) and
            (((time() - $timeout_initial_time) >= $timeout) or
            (($gantt->[$current_hole_index]->[0] == $gantt->[0]->[5]->[0]) and ($gantt->[$current_hole_index]->[1]->[$h]->[0] >= $gantt->[0]->[5]->[1])) or
            ($gantt->[$current_hole_index]->[0] > $gantt->[0]->[5]->[0]))){
            if (($gantt->[0]->[5]->[0] == $gantt->[$current_hole_index]->[0]) and
                ($gantt->[0]->[5]->[1] > $gantt->[$current_hole_index]->[1]->[$h]->[0])){
                $gantt->[0]->[5]->[1] = $gantt->[$current_hole_index]->[1]->[$h]->[0];
            }elsif ($gantt->[0]->[5]->[0] > $gantt->[$current_hole_index]->[0]){
                $gantt->[0]->[5]->[0] = $gantt->[$current_hole_index]->[0];
                $gantt->[0]->[5]->[1] = $gantt->[$current_hole_index]->[1]->[$h]->[0];
            }
            #print("TTTTTTT $gantt->[0]->[5]->[0] $gantt->[0]->[5]->[1] -- $gantt->[$current_hole_index]->[0] $gantt->[$current_hole_index]->[1]->[$h]->[0]\n");
            $current_time = $Infinity;
            @result_tree_list = ();
            $end_loop = 1;
        }
    }

    return($current_time, \@result_tree_list);
}

return 1;