import 'package:flutter/cupertino.dart';

class ListNotifier<T> extends ValueNotifier<List<T>> {
    ListNotifier(): super([]);

    void add(T value) {
        _changeList((list) => list.add(value));
    }
    
    void addAll(Iterable<T> iterable) {
        _changeList((list) => list.addAll(iterable));
    }
    
    bool remove(T value) {
        return _changeList((list) => list.remove(value));
    }
    
    T removeAt(int index) {
        return _changeList((list) => list.removeAt(index));
    }
    
    Y atValue<Y>(int index, Y Function(T value) fn) {
        return _changeList((list) => fn(list[index]));
    }
    
    T atRef(int index) => super.value[index];
    
    int len() => super.value.length;

    void clear() => super.value = [];

    Y _changeList<Y>(Y Function(List<T> list) fn) {
        final newList = super.value.toList();
        final result = fn(newList);
        super.value = newList;
        return result;
    }
}