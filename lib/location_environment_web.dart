import 'dart:js_interop';

@JS('window.isSecureContext')
external bool get locationContextIsSecure;

@JS('window')
external JSObject get _window;
@JS('window.top')
external JSObject? get _top;
@JS('Object.is')
external bool _sameObject(JSAny? first, JSAny? second);

bool get locationContextIsEmbedded => !_sameObject(_window, _top);
