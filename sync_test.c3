module atom::sync::test @test;

import atom;

def AtomFloat = Atom(<float>);

def CelciusToFahrenheit = atom::sync::AtoB(<float, float>);
def FahrenheitToCelcius = atom::sync::BtoA(<float, float>);
    
CelciusToFahrenheit celsius_to_fahrenheit = fn float! (float* celsius, any ctx  = null) {
    return (float)((*celsius * 9.0 / 5.0) + 32.0);
};

FahrenheitToCelcius fahrenheit_to_celsius = fn float! (float* fahrenheit, any ctx = null) {
    return (float)((*fahrenheit - 32.0) * 5.0 / 9.0);
};

fn void! sync_two_way() {
    AtomFloat* celsius_atom = atom::new_with_value(<float>)(25.0)!;
    AtomFloat* fahrenheit_atom = atom::new_with_value(<float>)(celsius_to_fahrenheit(celsius_atom.get()!))!;

    assert(fahrenheit_atom.try_get()! == 77.0, "Fahrenheit atom should be 77.0");

    Observable sync_signal = sync::new(<float, float>)(celsius_atom, fahrenheit_atom, celsius_to_fahrenheit, fahrenheit_to_celsius)!;

    fahrenheit_atom.set_value(140.0)!;    

    assert(celsius_atom.try_get()! == 60.0, "Celcius atom should be 60.0");

    celsius_atom.set_value(200.0)!;

    assert(fahrenheit_atom.try_get()! == 392.0, "Fahrenheit atom should be 392.0");
}
