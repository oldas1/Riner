//
//

#pragma once

#include <type_traits>

namespace miner {

    template<class T>
    struct void_ {
        using type = void;
    };

    template<class T, class = void>
    struct has_value_type : std::false_type {};

    template<class T>
    struct has_value_type<T, typename void_<typename T::value_type>::type>
            : std::true_type {};

    template<class T>
    constexpr bool has_value_type_v = has_value_type<T>::value;

}