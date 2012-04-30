package BusyBird::Connector;
use strict;
use warnings;

sub c {
    my ($self, $to, %connect_recipe) = @_;
    die (ref($self) . ' cannot connect to non-reference') if !ref($to);
    while(my ($recipe_class, $recipe_code) = each(%connect_recipe)) {
        if($to->isa($recipe_class)) {
            $recipe_code->();
            return $to;
        }
    }
    die (ref($self) . ' cannot connect to ' . ref($to));
    return $to;
}

1;

