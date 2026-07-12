// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_toggle_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LibraryToggleResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryToggleResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryToggleResult()';
}


}

/// @nodoc
class $LibraryToggleResultCopyWith<$Res>  {
$LibraryToggleResultCopyWith(LibraryToggleResult _, $Res Function(LibraryToggleResult) __);
}


/// Adds pattern-matching-related methods to [LibraryToggleResult].
extension LibraryToggleResultPatterns on LibraryToggleResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Added value)?  added,TResult Function( _Removed value)?  removed,TResult Function( _Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Added() when added != null:
return added(_that);case _Removed() when removed != null:
return removed(_that);case _Error() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Added value)  added,required TResult Function( _Removed value)  removed,required TResult Function( _Error value)  error,}){
final _that = this;
switch (_that) {
case _Added():
return added(_that);case _Removed():
return removed(_that);case _Error():
return error(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Added value)?  added,TResult? Function( _Removed value)?  removed,TResult? Function( _Error value)?  error,}){
final _that = this;
switch (_that) {
case _Added() when added != null:
return added(_that);case _Removed() when removed != null:
return removed(_that);case _Error() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool narouSyncFailed)?  added,TResult Function()?  removed,TResult Function()?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Added() when added != null:
return added(_that.narouSyncFailed);case _Removed() when removed != null:
return removed();case _Error() when error != null:
return error();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool narouSyncFailed)  added,required TResult Function()  removed,required TResult Function()  error,}) {final _that = this;
switch (_that) {
case _Added():
return added(_that.narouSyncFailed);case _Removed():
return removed();case _Error():
return error();case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool narouSyncFailed)?  added,TResult? Function()?  removed,TResult? Function()?  error,}) {final _that = this;
switch (_that) {
case _Added() when added != null:
return added(_that.narouSyncFailed);case _Removed() when removed != null:
return removed();case _Error() when error != null:
return error();case _:
  return null;

}
}

}

/// @nodoc


class _Added implements LibraryToggleResult {
  const _Added({this.narouSyncFailed = false});
  

/// なろう本家へのブックマーク同期に失敗したかどうか（ログイン中のみ意味を持つ）。
@JsonKey() final  bool narouSyncFailed;

/// Create a copy of LibraryToggleResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddedCopyWith<_Added> get copyWith => __$AddedCopyWithImpl<_Added>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Added&&(identical(other.narouSyncFailed, narouSyncFailed) || other.narouSyncFailed == narouSyncFailed));
}


@override
int get hashCode => Object.hash(runtimeType,narouSyncFailed);

@override
String toString() {
  return 'LibraryToggleResult.added(narouSyncFailed: $narouSyncFailed)';
}


}

/// @nodoc
abstract mixin class _$AddedCopyWith<$Res> implements $LibraryToggleResultCopyWith<$Res> {
  factory _$AddedCopyWith(_Added value, $Res Function(_Added) _then) = __$AddedCopyWithImpl;
@useResult
$Res call({
 bool narouSyncFailed
});




}
/// @nodoc
class __$AddedCopyWithImpl<$Res>
    implements _$AddedCopyWith<$Res> {
  __$AddedCopyWithImpl(this._self, this._then);

  final _Added _self;
  final $Res Function(_Added) _then;

/// Create a copy of LibraryToggleResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? narouSyncFailed = null,}) {
  return _then(_Added(
narouSyncFailed: null == narouSyncFailed ? _self.narouSyncFailed : narouSyncFailed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class _Removed implements LibraryToggleResult {
  const _Removed();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Removed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryToggleResult.removed()';
}


}




/// @nodoc


class _Error implements LibraryToggleResult {
  const _Error();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Error);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryToggleResult.error()';
}


}




// dart format on
