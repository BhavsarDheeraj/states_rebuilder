import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:states_rebuilder/src/inject.dart';
import 'package:states_rebuilder/src/injector.dart';
import 'package:states_rebuilder/src/reactive_model.dart';
import 'package:states_rebuilder/src/reactive_model_imp.dart';
import 'package:states_rebuilder/src/rm_key.dart';
import 'package:states_rebuilder/src/state_builder.dart';

void main() {
  ReactiveModel<Model> modelRM;

  setUp(() {
    final inject = Inject(() => Model());
    modelRM = inject.getReactive()..listenToRM((rm) {});
  });

  tearDown(() {
    modelRM = null;
  });

  test('ReactiveModel: get the state with the right status', () {
    expect(modelRM.state, isA<Model>());
    expect(modelRM.snapshot.data, isA<Model>());
    expect(modelRM.connectionState, equals(ConnectionState.none));
    expect(modelRM.hasData, isFalse);

    modelRM.setState(null);
    expect(modelRM.connectionState, equals(ConnectionState.done));
    expect(modelRM.hasData, isTrue);
  });

  test(
    'ReactiveModel: throw error if error is not caught',
    () {
      //throw
      expect(
          () => modelRM.setState((s) => s.incrementError()), throwsException);
      //do not throw
      modelRM.setState((s) => s.incrementError(), catchError: true);
    },
  );

  test('ReactiveModel: get the error', () {
    modelRM.setState((s) => s.incrementError(), catchError: true);

    expect(modelRM.error.message, equals('error message'));
    expect(
        (modelRM.snapshot.error as dynamic).message, equals('error message'));
    expect(modelRM.hasError, isTrue);
  });

  test('call global error handler without observers', () {
    BuildContext ctx;
    var error;
    final rm = RM.create(0)
      ..onError((context, e) {
        ctx = context;
        error = e;
      });

    rm.setState(
      (_) {
        throw Exception();
      },
      silent: true,
      catchError: true,
    );

    expect(rm.hasError, isTrue);
    expect(ctx, isNull);
    expect(error, isA<Exception>());
  });

  testWidgets(
    'ReactiveModel: Subscribe using StateBuilder and setState mutate the state and notify observers',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (context, __) {
          return _widgetBuilder('${modelRM.state.counter}');
        },
      );
      await tester.pumpWidget(widget);
      //
      modelRM.setState((s) => s.increment());
      expect(RM.notified.isA<Model>(), isTrue);
      await tester.pump();
      expect(find.text(('1')), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: catch sync error and notify observers',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return _widgetBuilder(
            '${modelRM.state.counter}',
            '${modelRM.error?.message}',
          );
        },
      );
      await tester.pumpWidget(widget);
      expect(find.text(('error message')), findsNothing);
      //
      modelRM.setState((s) {
        s.incrementError();
      }, catchError: true);
      await tester.pump();
      expect(find.text(('error message')), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: call async method without error and notify observers',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return _widgetBuilder(
            '${modelRM.state.counter}',
            'isWaiting=${modelRM.isWaiting}',
            'isIdle=${modelRM.isIdle}',
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(find.text('0'), findsOneWidget);
      expect(find.text('isWaiting=false'), findsOneWidget);
      expect(find.text('isIdle=true'), findsOneWidget);
      expect(modelRM.stateAsync, isA<Future<Model>>());
      modelRM.setState((s) async {
        await s.incrementAsync();
      });
      await tester.pump();
      //isWaiting
      expect(find.text('0'), findsOneWidget);
      expect(find.text('isWaiting=true'), findsOneWidget);
      expect(find.text('isIdle=false'), findsOneWidget);
      expect(modelRM.stateAsync, isA<Future<Model>>());

      await tester.pump(Duration(seconds: 1));
      //hasData
      expect(find.text('1'), findsOneWidget);
      expect(find.text('isWaiting=false'), findsOneWidget);
      expect(find.text('isIdle=false'), findsOneWidget);
      expect((await modelRM.stateAsync).counter, 1);
    },
  );

  testWidgets(
    'ReactiveModel: call async method with error and notify observers',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return _widgetBuilder(
            '${modelRM.hasError ? modelRM.error.message : modelRM.state.counter}',
            'isWaiting=${modelRM.isWaiting}',
            'isIdle=${modelRM.isIdle}',
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(find.text('0'), findsOneWidget);
      expect(find.text('isWaiting=false'), findsOneWidget);
      expect(find.text('isIdle=true'), findsOneWidget);

      modelRM.setState((s) => s.incrementAsyncError(), catchError: true);
      await tester.pump();
      //isWaiting
      expect(find.text('0'), findsOneWidget);
      expect(find.text('isWaiting=true'), findsOneWidget);
      expect(find.text('isIdle=false'), findsOneWidget);
      await tester.pump(Duration(seconds: 1));
      //hasData
      expect(find.text('Error message'), findsOneWidget);
      expect(find.text('isWaiting=false'), findsOneWidget);
      expect(find.text('isIdle=false'), findsOneWidget);
      modelRM.stateAsync.catchError((e) {
        expect(e.message, 'Error message');
      });
    },
  );

  testWidgets(
    'ReactiveModel: whenConnectionState should work',
    (tester) async {
      RM.debugWidgetsRebuild = true;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        key: Key('whenConnectionState'),
        builder: (_, __) {
          return modelRM.whenConnectionState(
            onIdle: () => _widgetBuilder('onIdle'),
            onWaiting: () => _widgetBuilder('onWaiting'),
            onData: (data) => _widgetBuilder('${data.counter}'),
            onError: (error) => _widgetBuilder('${error.message}'),
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(find.text('onIdle'), findsOneWidget);

      modelRM.setState((s) => s.incrementAsync());
      await tester.pump();
      //isWaiting
      expect(find.text('onWaiting'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //hasData
      expect(find.text('1'), findsOneWidget);

      //throw error
      modelRM.setState((s) => s.incrementAsyncError());
      await tester.pump();
      //isWaiting
      expect(find.text('onWaiting'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //hasError
      expect(find.text('Error message'), findsOneWidget);

      //throw error
      modelRM.setState((s) => s.incrementAsyncError());
      await tester.pump();
      //isWaiting
      expect(find.text('onWaiting'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //hasError
      expect(find.text('Error message'), findsOneWidget);
      RM.debugWidgetsRebuild = false;
    },
  );

  testWidgets(
    'ReactiveModel: with whenConnectionState error should be catch',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return modelRM.whenConnectionState(
            onIdle: () => _widgetBuilder('onIdle'),
            onWaiting: () => _widgetBuilder('onWaiting'),
            onData: (data) => _widgetBuilder('${data.counter}'),
            onError: (error) => _widgetBuilder('${error.message}'),
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(find.text('onIdle'), findsOneWidget);

      modelRM.setState((s) => s.incrementError());
      await tester.pump();
      //hasError
      expect(find.text('error message'), findsOneWidget);
      //
      modelRM.setState((s) => s.incrementError());
      await tester.pump();
      //hasError
      expect(find.text('error message'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: watch state mutating before notify observers, sync method',
    (tester) async {
      int numberOfRebuild = 0;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          numberOfRebuild++;
          return modelRM.whenConnectionState(
            onIdle: () => _widgetBuilder('onIdle'),
            onWaiting: () => _widgetBuilder('onWaiting'),
            onData: (data) => _widgetBuilder('${data.counter}'),
            onError: (error) => _widgetBuilder('${error.message}'),
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(numberOfRebuild, equals(1));
      expect(find.text('onIdle'), findsOneWidget);

      modelRM.setState(
        (s) => s.increment(),
        watch: (s) {
          return s.counter;
        },
      );
      await tester.pump();
      //will rebuild
      expect(numberOfRebuild, equals(2));
      expect(find.text('1'), findsOneWidget);
      //will not rebuild
      modelRM.setState(
        (s) => s.increment(),
        watch: (s) {
          return 1;
        },
      );
      await tester.pump();
      //
      expect(numberOfRebuild, equals(2));
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: watch state mutating before notify observers, async method',
    (tester) async {
      int numberOfRebuild = 0;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          numberOfRebuild++;
          return modelRM.whenConnectionState(
            onIdle: () => _widgetBuilder('onIdle'),
            onWaiting: () => _widgetBuilder('onWaiting'),
            onData: (data) => _widgetBuilder('${data.counter}'),
            onError: (error) => _widgetBuilder('${error.message}'),
          );
        },
      );
      await tester.pumpWidget(widget);

      expect(numberOfRebuild, equals(1));
      expect(find.text('onIdle'), findsOneWidget);

      modelRM.setState(
        (s) => s.incrementAsync(),
        watch: (s) {
          return 0;
        },
      );
      await tester.pump();
      //will not rebuild
      expect(numberOfRebuild, equals(1));
      expect(find.text('onIdle'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //will not rebuild
      expect(numberOfRebuild, equals(1));
      expect(find.text('onIdle'), findsOneWidget);

      //
      modelRM.setState(
        (s) => s.incrementAsync(),
        watch: (s) {
          return s.counter;
        },
      );
      await tester.pump();
      //will not rebuild
      expect(numberOfRebuild, equals(1));
      expect(find.text('onIdle'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //will rebuild
      expect(numberOfRebuild, equals(2));
      expect(find.text('2'), findsOneWidget);

      //
      modelRM.setState(
        (s) => s.incrementAsync(),
        watch: (s) {
          return 1;
        },
      );
      await tester.pump();
      //will not rebuild
      expect(numberOfRebuild, equals(2));
      expect(find.text('2'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //will not rebuild
      expect(numberOfRebuild, equals(2));
      expect(find.text('2'), findsOneWidget);

      //
      modelRM.setState(
        (s) => s.incrementAsync(),
        watch: (s) {
          return s.counter;
        },
      );
      await tester.pump();
      //will not rebuild
      expect(numberOfRebuild, equals(2));
      expect(find.text('2'), findsOneWidget);

      await tester.pump(Duration(seconds: 1));
      //will rebuild
      expect(numberOfRebuild, equals(3));
      expect(find.text('4'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: tagFilter works',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        tag: 'tag1',
        builder: (_, __) {
          return modelRM.whenConnectionState(
            onIdle: () => _widgetBuilder('onIdle'),
            onWaiting: () => _widgetBuilder('onWaiting'),
            onData: (data) => _widgetBuilder('${data.counter}'),
            onError: (error) => _widgetBuilder('${error.message}'),
          );
        },
      );
      await tester.pumpWidget(widget);
      //isIdle
      expect(find.text('onIdle'), findsOneWidget);
      //rebuildAll
      modelRM.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      //rebuild with tag 'tag1'
      modelRM.setState((s) => s.increment(), filterTags: ['tag1']);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      //rebuild with tag 'nonExistingTag'
      modelRM.setState((s) => s.increment(), filterTags: ['nonExistingTag']);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel: onSetState and onRebuildState work',
    (tester) async {
      int numberOfOnSetStateCall = 0;
      int numberOfOnRebuildStateCall = 0;
      BuildContext contextFromOnSetState;
      BuildContext contextFromOnRebuildState;
      String lifeCycleTracker = '';
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          lifeCycleTracker += 'build, ';
          return Container();
        },
      );
      await tester.pumpWidget(widget);
      expect(numberOfOnSetStateCall, equals(0));
      //
      modelRM.setState(
        (s) => s.increment(),
        onSetState: (context) {
          numberOfOnSetStateCall++;
          contextFromOnSetState = context;
          lifeCycleTracker += 'onSetState, ';
        },
        onRebuildState: (context) {
          numberOfOnRebuildStateCall++;
          contextFromOnRebuildState = context;
          lifeCycleTracker += 'onRebuildState, ';
        },
      );
      await tester.pump();
      expect(numberOfOnSetStateCall, equals(1));
      expect(contextFromOnSetState, isNotNull);
      expect(numberOfOnRebuildStateCall, equals(1));
      expect(contextFromOnRebuildState, isNotNull);
      expect(lifeCycleTracker,
          equals('build, onSetState, build, onRebuildState, '));
    },
  );

  testWidgets(
    'ReactiveModel: onData work for sync call',
    (tester) async {
      int numberOfOnDataCall = 0;
      BuildContext contextFromOnData;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return Container();
        },
      );
      await tester.pumpWidget(widget);
      expect(numberOfOnDataCall, equals(0));
      expect(contextFromOnData, isNull);
      //
      modelRM.setState(
        (s) => s.increment(),
        onData: (context, data) {
          contextFromOnData = context;
          numberOfOnDataCall++;
        },
      );
      await tester.pump();
      expect(numberOfOnDataCall, equals(1));
      expect(contextFromOnData, isNotNull);
    },
  );

  testWidgets(
    'ReactiveModel: onData work for async call',
    (tester) async {
      int numberOfOnDataCall = 0;
      BuildContext contextFromOnData;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return Container();
        },
      );
      await tester.pumpWidget(widget);
      expect(numberOfOnDataCall, equals(0));
      expect(contextFromOnData, isNull);

      //
      modelRM.setState(
        (s) => s.incrementAsync(),
        onData: (context, data) {
          contextFromOnData = context;
          numberOfOnDataCall++;
        },
      );
      await tester.pump();
      expect(numberOfOnDataCall, equals(0));
      await tester.pump(Duration(seconds: 1));
      expect(numberOfOnDataCall, equals(1));
      expect(contextFromOnData, isNotNull);
    },
  );

  testWidgets(
    'ReactiveModel: onError work for sync call',
    (tester) async {
      int numberOfOnErrorCall = 0;
      BuildContext contextFromOnError;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return Container();
        },
      );
      await tester.pumpWidget(widget);
      expect(numberOfOnErrorCall, equals(0));
      expect(contextFromOnError, isNull);
      //
      modelRM.setState(
        (s) => s.incrementError(),
        onError: (context, data) {
          numberOfOnErrorCall++;
          contextFromOnError = context;
        },
      );
      await tester.pump();
      expect(numberOfOnErrorCall, equals(1));
      expect(contextFromOnError, isNotNull);
    },
  );

  testWidgets(
    'ReactiveModel: onError work for async call',
    (tester) async {
      int numberOfOnErrorCall = 0;
      BuildContext contextFromOnError;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return Container();
        },
      );
      await tester.pumpWidget(widget);
      expect(numberOfOnErrorCall, equals(0));
      expect(contextFromOnError, isNull);
      //
      modelRM.setState(
        (s) => s.incrementAsyncError(),
        onError: (context, data) {
          numberOfOnErrorCall++;
          contextFromOnError = context;
        },
      );
      await tester.pump();
      expect(numberOfOnErrorCall, equals(0));
      expect(contextFromOnError, isNull);
      //
      await tester.pump(Duration(seconds: 1));
      expect(numberOfOnErrorCall, equals(1));
      expect(contextFromOnError, isNotNull);
    },
  );

  testWidgets(
    'ReactiveModel : reactive singleton and reactive instances works independently',
    (tester) async {
      final inject = Inject(() => Model());
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);
      //
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate singleton
      modelRM0.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-3'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel : new reactive notify reactive singleton with its state if joinSingleton = withNewReactiveInstance',
    (tester) async {
      final inject = Inject(
        () => Model(),
        joinSingleton: JoinSingleton.withNewReactiveInstance,
      );
      final modelRM2 = inject.getReactive(true);
      final modelRM1 = inject.getReactive(true);
      final modelRM0 = inject.getReactive();

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment());
      await tester.pump();

      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate reactive instance 1
      modelRM2.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel : (case Inject.interface)new reactive notify reactive singleton with its state if joinSingleton = withNewReactiveInstance',
    (tester) async {
      Injector.env = 'prod';
      final inject = Inject.interface(
        {'prod': () => Model()},
        joinSingleton: JoinSingleton.withNewReactiveInstance,
      );
      final modelRM2 = inject.getReactive(true);
      final modelRM1 = inject.getReactive(true);
      final modelRM0 = inject.getReactive();

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment());
      await tester.pump();

      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate reactive instance 1
      modelRM2.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
    },
  );

  testWidgets(
    'ReactiveModel : singleton holds the combined state of new instances if joinSingleton = withCombinedReactiveInstances case sync with error call',
    (tester) async {
      final inject = Inject(
        () => Model(),
        joinSingleton: JoinSingleton.withCombinedReactiveInstances,
      );
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      expect(modelRM0.isIdle, isTrue);
      expect(modelRM1.isIdle, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.isIdle, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.incrementError());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.incrementError());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-1'), findsOneWidget);

      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-1'), findsOneWidget);

      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.increment());
      await tester.pump();
      expect(find.text('modelRM0-3'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-3'), findsOneWidget);

      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasData, isTrue);
    },
  );

  testWidgets(
    'ReactiveModel : singleton holds the combined state of new instances if joinSingleton = withCombinedReactiveInstances case async wth error call',
    (tester) async {
      final inject = Inject(
        () => Model(),
        joinSingleton: JoinSingleton.withCombinedReactiveInstances,
      );
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.incrementAsyncError());
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.isWaiting, isTrue);
      expect(modelRM1.isWaiting, isTrue);
      expect(modelRM2.isIdle, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.incrementAsyncError());
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      expect(modelRM0.isWaiting, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.isWaiting, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.incrementAsync());
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.isWaiting, isTrue);
      expect(modelRM1.isWaiting, isTrue);
      expect(modelRM2.hasError, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.incrementAsync());
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-1'), findsOneWidget);
      expect(modelRM0.isWaiting, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.isWaiting, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasData, isTrue);
    },
  );

  testWidgets(
    'ReactiveModel : join singleton to new reactive from setState',
    (tester) async {
      final inject = Inject(() => Model());
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 1
      modelRM1.setState(
        (s) => s.incrementError(),
        joinSingleton: true,
        catchError: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 2
      modelRM2.setState(
        (s) => s.incrementError(),
        joinSingleton: true,
        catchError: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.hasError, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment(), joinSingleton: true);
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.increment(), joinSingleton: true);
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.hasData, isTrue);
      expect(modelRM2.hasData, isTrue);
    },
  );

  testWidgets(
    'ReactiveModel : notify all reactive instances to new reactive from setState',
    (tester) async {
      final inject = Inject(() => Model());
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 0
      modelRM0.setState(
        (s) => s.incrementError(),
        notifyAllReactiveInstances: true,
        catchError: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-0'), findsOneWidget);
      expect(find.text('modelRM1-0'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
      expect(modelRM1.isIdle, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 0
      modelRM0.setState(
        (s) => s.increment(),
        notifyAllReactiveInstances: true,
        catchError: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-1'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.isIdle, isTrue);
      expect(modelRM2.isIdle, isTrue);

      //mutate reactive instance 1
      modelRM2.setState(
        (s) => s.incrementError(),
        notifyAllReactiveInstances: true,
        catchError: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-1'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.isIdle, isTrue);
      expect(modelRM2.hasError, isTrue);

      //mutate reactive instance 0
      modelRM2.setState(
        (s) => s.increment(),
        notifyAllReactiveInstances: true,
      );
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
      expect(modelRM1.isIdle, isTrue);
      expect(modelRM2.hasData, isTrue);
    },
  );

  testWidgets(
    'ReactiveModel : join singleton to new reactive from setState with data send using joinSingletonToNewData',
    (tester) async {
      final inject = Inject(() => Model());
      final modelRM0 = inject.getReactive();
      final modelRM1 = inject.getReactive(true);
      final modelRM2 = inject.getReactive(true);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder(
                  'modelRM0-${modelRM0.joinSingletonToNewData}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //mutate reactive instance 1
      modelRM1.setState((s) => s.increment(),
          joinSingleton: true,
          catchError: true,
          joinSingletonToNewData: () => 'modelRM1-${modelRM1.state.counter}');
      await tester.pump();
      expect(find.text('modelRM0-modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //mutate reactive instance 2
      modelRM2.setState((s) => s.increment(),
          joinSingleton: true,
          catchError: true,
          joinSingletonToNewData: () => 'modelRM2-${modelRM1.state.counter}');
      await tester.pump();
      expect(find.text('modelRM0-modelRM2-2'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);
    },
  );

  testWidgets(
      'ReactiveModel : throws if setState is called on async injected models',
      (tester) async {
    final inject = Inject.future(() => getFuture());
    final modelRM0 = inject.getReactive();
    expect(() => modelRM0.setState(null), throwsException);
    await tester.pump(Duration(seconds: 1));
  });

  testWidgets(
    'ReactiveModel : inject futures with data works',
    (tester) async {
      final inject = Inject.future(() => getFuture());
      final modelRM0 = inject.getReactive();

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('${modelRM0.state}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      expect(find.text('null'), findsOneWidget);
      expect(modelRM0.isWaiting, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(modelRM0.hasData, isTrue);
    },
  );

  testWidgets(
    'ReactiveModel : inject futures with error works',
    (tester) async {
      final inject = Inject.future(() => getFutureWithError());
      final modelRM0 = inject.getReactive();

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('${modelRM0.state}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);
      expect(modelRM0.isA<Future<int>>(), isTrue);
      expect(find.text('null'), findsOneWidget);
      expect(modelRM0.isWaiting, isTrue);
      await tester.pump(Duration(seconds: 1));
      expect(find.text('null'), findsOneWidget);
      expect(modelRM0.hasError, isTrue);
    },
  );

  group('future', () {
    testWidgets(
      'ReactiveModel : inject futures with tag filter works ',
      (tester) async {
        final inject = Inject.future(() => getFuture(), filterTags: ['tag1']);
        final modelRM0 = inject.getReactive();

        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observeMany: [() => modelRM0],
              tag: 'tag1',
              builder: (context, _) {
                return _widgetBuilder('tag1-${modelRM0.state}');
              },
            ),
            StateBuilder(
              observeMany: [() => modelRM0],
              builder: (context, _) {
                return _widgetBuilder('${modelRM0.state}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);

        expect(find.text('tag1-null'), findsOneWidget);
        expect(find.text('null'), findsOneWidget);
        expect(modelRM0.isWaiting, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('tag1-1'), findsOneWidget);
        expect(find.text('null'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);
      },
    );

    testWidgets(
      'ReactiveModel : ReactiveModel.future works',
      (tester) async {
        final rmKey = RMKey<int>(0);
        final widget = Column(
          children: <Widget>[
            StateBuilder<int>(
              observe: () => RM.future(getFuture(), initialValue: 0),
              rmKey: rmKey,
              builder: (context, _) {
                return Container();
              },
            ),
            StateBuilder(
              observe: () => rmKey,
              builder: (_, rm) {
                return Text(rm.state.toString());
              },
            ),
          ],
        );

        await tester.pumpWidget(MaterialApp(home: widget));
        expect(find.text('0'), findsOneWidget);
        expect(rmKey.isWaiting, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(rmKey.hasData, isTrue);
      },
    );

    testWidgets(
      'ReactiveModel : future method works',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              //used to add observer so to throw FlutterError
              observe: () => modelRM,
              builder: (context, modelRM) {
                return Container();
              },
            ),
            StateBuilder<Model>(
              observe: () => modelRM
                ..setState((m) => m.incrementAsync())
                ..onError((context, error) {
                  errorMessage = error.message;
                }),
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            ),
            StateBuilder<Model>(
              //used to add observer so to throw FlutterError
              observe: () => modelRM,
              builder: (context, modelRM) {
                return Container();
              },
            ),
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);
      },
    );

    testWidgets(
      'ReactiveModel : future method works, case with error',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              observe: () => modelRM,
              builder: (context, modelRM) {
                return Container();
              },
            ),
            StateBuilder<Model>(
              observe: () => modelRM
                ..setState((m) => m.incrementAsyncError())
                ..onError((context, error) {
                  errorMessage = error.message;
                }),
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );

    testWidgets(
      'ReactiveModel : future method works, call future from initState',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              observe: () => modelRM,
              builder: (context, modelRM) {
                return Container();
              },
            ),
            StateBuilder<Model>(
              observe: () => modelRM,
              initState: (_, modelRM) => modelRM
                ..setState((m) => m.incrementAsyncError())
                ..onError((context, error) {
                  errorMessage = error.message;
                }),
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );

    testWidgets(
      'Nested dependent futures ',
      (tester) async {
        final future1 =
            RM.future(Future.delayed(Duration(seconds: 1), () => 2));
        final inject = Inject.future(() async {
          final future1Value = await future1.stateAsync;
          await Future.delayed(Duration(seconds: 1));
          return future1Value * 2;
        });
        final future2 = inject.getReactive();
        expect(future1.isWaiting, isTrue);
        expect(future2.isWaiting, isTrue);
        await tester.pump(Duration(seconds: 1));
        expect(future1.hasData, isTrue);
        expect(future2.isWaiting, isTrue);
        future2.setState(
          (future) => Future.delayed(Duration(seconds: 1), () => 2 * future),
          silent: true,
          shouldAwait: true,
        );
        await tester.pump(Duration(seconds: 1));
        expect(future1.state, 2);
        expect(future2.isWaiting, isTrue);
        await tester.pump(Duration(seconds: 1));
        expect(future1.state, 2);
        expect(future2.state, 8);
      },
    );
  });
  group('stream', () {
    testWidgets(
      'ReactiveModel : inject stream with data works',
      (tester) async {
        final inject = Inject.stream(() => getStream(), initialValue: 0);
        final modelRM0 = inject.getReactive();

        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observeMany: [() => modelRM0],
              builder: (context, _) {
                return _widgetBuilder('${modelRM0.state}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM0.isWaiting, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('0'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);

        await tester.pump(Duration(seconds: 1));

        expect(find.text('2'), findsOneWidget);
        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'ReactiveModel : inject stream with data and error works',
      (tester) async {
        final ReactiveModelImp<int> modelRM0 =
            RM.stream(Model().incrementStream(), initialValue: 0);

        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observe: () => modelRM0,
              builder: (context, modelRM0) {
                return _widgetBuilder('${modelRM0.state}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM0.isWaiting, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM0.hasError, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM0.isStreamDone, isTrue);
      },
    );
    testWidgets(
      'ReactiveModel : inject stream with watching data works',
      (tester) async {
        final inject = Inject.stream(() => getStream(), watch: (data) {
          return 0;
        });
        final modelRM0 = inject.getReactive();
        int numberOfRebuild = 0;
        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observeMany: [() => modelRM0],
              builder: (context, _) {
                numberOfRebuild++;
                return _widgetBuilder('${modelRM0.state}-$numberOfRebuild');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);

        expect(find.text('null-1'), findsOneWidget);
        expect(modelRM0.isWaiting, isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('null-1'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);

        // await tester.pump(Duration(seconds: 1));
        // expect(find.text('null-1'), findsOneWidget);
        // expect(modelRM0.hasData, isTrue);

        // await tester.pump(Duration(seconds: 1));
        // expect(find.text('null-1'), findsOneWidget);
      },
    );
    testWidgets(
      'issue #61: reactive stream with error and watch',
      (WidgetTester tester) async {
        int numberOfRebuild = 0;
        Stream<int> snapStream = Stream.periodic(Duration(seconds: 1), (num) {
          if (num == 0) throw Exception('error message');
          return num + 1;
        }).take(3);

        final rmStream = ReactiveModel.stream(snapStream,
            watch: (rm) => rm, initialValue: 0);
        final widget = Injector(
          inject: [Inject(() => 'n')],
          builder: (_) {
            return StateBuilder(
              observeMany: [() => rmStream],
              tag: 'MyTag',
              builder: (_, rmStream) {
                numberOfRebuild++;
                return Container();
              },
            );
          },
        );

        await tester.pumpWidget(MaterialApp(home: widget));
        expect(numberOfRebuild, 1);
        expect(rmStream.state, 0);

        await tester.pump(Duration(seconds: 1));
        expect(numberOfRebuild, 2);
        expect(rmStream.state, 0);

        await tester.pump(Duration(seconds: 1));
        expect(numberOfRebuild, 3);
        expect(rmStream.state, 2);

        await tester.pump(Duration(seconds: 1));
        expect(numberOfRebuild, 4);
        expect(rmStream.state, 3);

        await tester.pump(Duration(seconds: 1));
        expect(numberOfRebuild, 5);
        expect(rmStream.state, 4);

        await tester.pump(Duration(seconds: 1));
        expect(numberOfRebuild, 5);
        expect(rmStream.state, 4);
      },
    );

    testWidgets(
      'ReactiveModel : stream method works. case stream called from observe parameter',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              observe: () => modelRM
                ..setState((m) => m.incrementStream())
                ..onError((context, error) {
                  errorMessage = error.message;
                }),
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );

    testWidgets(
      'ReactiveModel : stream method works. case stream called from outside',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              observe: () => modelRM,
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        modelRM
          ..setState((m) => m.incrementStream())
          ..onError((context, error) {
            errorMessage = error.message;
          });
        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );

    testWidgets(
      'ReactiveModel : stream method works with new ReactiveModel',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        ReactiveModel<Model> newModelRM = modelRM.asNew('newRM');
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<Model>(
              observeMany: [() => modelRM, () => newModelRM],
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        newModelRM
          ..setState((m) => m.incrementStream())
          ..onError((context, error) {
            errorMessage = error.message;
          });
        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isIdle, isTrue);
        expect(newModelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.isIdle, isTrue);
        expect(newModelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
        expect(newModelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.isIdle, isTrue);
        expect(newModelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );
    testWidgets(
      'ReactiveModel : stream method works. ImmutableModel',
      (tester) async {
        ReactiveModel<ImmutableModel> modelRM = RM.create(ImmutableModel(0));
        String errorMessage;
        final widget = Column(
          children: <Widget>[
            StateBuilder<ImmutableModel>(
              observe: () => modelRM,
              builder: (context, modelRM) {
                return _widgetBuilder('${modelRM.state.counter}');
              },
            )
          ],
        );

        modelRM
          ..setState((m) => m.incrementStream())
          ..onError((context, error) {
            errorMessage = error.message;
          });
        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.isWaiting, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsOneWidget);
        expect(modelRM.hasData, isTrue);
        expect(errorMessage, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('0'), findsOneWidget);
        expect(modelRM.hasError, isTrue);
        expect(errorMessage, 'Error message');
      },
    );

    testWidgets(
      'Injector  will  stream dispose if ',
      (tester) async {
        ReactiveModel<Model> modelRM = RM.create(Model());
        final rmKey = RMKey(true);
        final widget = StateBuilder(
            observe: () => RM.create(true),
            rmKey: rmKey,
            tag: 'tag1',
            builder: (context, switcherRM) {
              if (switcherRM.state) {
                return StateBuilder<Model>(
                  observe: () => modelRM,
                  builder: (context, modelRM) {
                    return _widgetBuilder('${modelRM.state.counter}');
                  },
                );
              } else {
                return Container();
              }
            });
        final streamRM = modelRM..setState((m) => m.incrementStream());

        await tester.pumpWidget(widget);
        expect(find.text('0'), findsOneWidget);
        expect(streamRM.isA<Model>(), isTrue);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(streamRM.subscription.isPaused, isFalse);

        rmKey.state = false;
        await tester.pump();

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsNothing);
        expect(streamRM.subscription, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('2'), findsNothing);
      },
    );
  });

  group('ReactiveModel setValue :', () {
    testWidgets(
      'tagFilter works',
      (tester) async {
        final modelRM = RM.create(0);

        final widget = StateBuilder(
          observeMany: [() => modelRM],
          tag: 'tag1',
          builder: (_, __) {
            return _widgetBuilder('${modelRM.state}');
          },
        );
        await tester.pumpWidget(widget);
        modelRM.setState((_) => modelRM.state + 1);
        await tester.pump();
        expect(find.text(('1')), findsOneWidget);

        await tester.pumpWidget(widget);
        modelRM.setState((_) => modelRM.state + 1, filterTags: ['tag1']);
        await tester.pump();
        expect(find.text(('2')), findsOneWidget);
        await tester.pumpWidget(widget);
        modelRM
            .setState((_) => modelRM.state + 1, filterTags: ['nonExistingTag']);
        await tester.pump();
        expect(find.text(('2')), findsOneWidget);
      },
    );

    testWidgets(
      'if the value does not changed do not rebuild',
      (tester) async {
        final modelRM = ReactiveModel.create(0);
        int numberOfRebuild = 0;
        final widget = StateBuilder(
          observeMany: [() => modelRM],
          tag: 'tag1',
          builder: (_, __) {
            return _widgetBuilder('${++numberOfRebuild}');
          },
        );
        await tester.pumpWidget(widget);
        expect(find.text(('1')), findsOneWidget);

        modelRM.setState((_) => modelRM.state);
        await tester.pump();
        expect(find.text(('1')), findsOneWidget);

        modelRM.setState((_) => modelRM.state + 1);
        await tester.pump();
        expect(find.text(('2')), findsOneWidget);
      },
    );

    testWidgets(
      'onSetState and onRebuildState work',
      (tester) async {
        final ReactiveModelImp<int> modelRM =
            ReactiveModelImp<int>(Inject(() => 0));

        int numberOfOnSetStateCall = 0;
        int numberOfOnRebuildStateCall = 0;
        BuildContext contextFromOnSetState;
        BuildContext contextFromOnRebuildState;
        String lifeCycleTracker = '';
        final widget = StateBuilder(
          observeMany: [() => modelRM],
          builder: (_, __) {
            lifeCycleTracker += 'build, ';
            return Container();
          },
        );
        await tester.pumpWidget(widget);
        expect(numberOfOnSetStateCall, equals(0));
        //
        modelRM.setState(
          (_) => modelRM.state + 1,
          onSetState: (context) {
            numberOfOnSetStateCall++;
            contextFromOnSetState = context;
            lifeCycleTracker += 'onSetState, ';
          },
          onRebuildState: (context) {
            numberOfOnRebuildStateCall++;
            contextFromOnRebuildState = context;
            lifeCycleTracker += 'onRebuildState, ';
          },
        );
        await tester.pump();
        expect(numberOfOnSetStateCall, equals(1));
        expect(contextFromOnSetState, isNotNull);
        expect(numberOfOnRebuildStateCall, equals(1));
        expect(contextFromOnRebuildState, isNotNull);
        expect(lifeCycleTracker,
            equals('build, onSetState, build, onRebuildState, '));
      },
    );

    testWidgets(
      'sync methods with and without error work',
      (tester) async {
        final modelRM = ReactiveModel.create(0);

        final widget = StateBuilder(
          observeMany: [() => modelRM],
          builder: (_, __) {
            return modelRM.whenConnectionState(
              onIdle: () => _widgetBuilder('onIdle'),
              onWaiting: () => _widgetBuilder('onWaiting'),
              onData: (data) => _widgetBuilder('${data}'),
              onError: (error) => _widgetBuilder('${error.message}'),
            );
          },
        );
        await tester.pumpWidget(widget);
        //sync increment without error
        modelRM.setState((_) {
          final model = Model();
          model.increment();
          return model.counter;
        });
        await tester.pump();
        expect(find.text(('1')), findsOneWidget);

        //sync increment with error
        var error;
        await modelRM.setState(
          (_) {
            final model = Model();
            model.incrementError();
            return model.counter;
          },
          onError: (_, e) {
            error = e;
          },
          catchError: true,
        );
        await tester.pump();
        expect(find.text('error message'), findsOneWidget);
        expect(error.message, equals('error message'));
      },
    );

    testWidgets(
      'seeds works',
      (tester) async {
        final modelRM0 = ReactiveModel.create(0);
        final modelRM1 = modelRM0.asNew('seed1');
        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observeMany: [() => modelRM0],
              builder: (_, __) {
                return _widgetBuilder('model0-${modelRM0.state}');
              },
            ),
            StateBuilder(
              observeMany: [() => modelRM1],
              builder: (_, __) {
                return _widgetBuilder('model1-${modelRM1.state}');
              },
            )
          ],
        );
        await tester.pumpWidget(widget);
        modelRM0.setState((_) => modelRM0.state + 1);
        await tester.pump();
        expect(find.text(('model0-1')), findsOneWidget);
        expect(find.text(('model1-0')), findsOneWidget);
        //
        modelRM0.setState((_) => modelRM0.state + 1, seeds: ['seed1']);
        await tester.pump();
        expect(find.text(('model0-2')), findsOneWidget);
        expect(find.text(('model1-2')), findsOneWidget);
        //
        modelRM1.setState((_) {
          return modelRM1.state + 1;
        });
        await tester.pump();
        expect(find.text(('model0-2')), findsOneWidget);
        expect(find.text(('model1-3')), findsOneWidget);
        //
        modelRM1.setState(
          (_) {
            return modelRM1.state + 1;
          },
          notifyAllReactiveInstances: true,
        );
        await tester.pump();
        expect(find.text(('model0-4')), findsOneWidget);
        expect(find.text(('model1-4')), findsOneWidget);
      },
    );

    testWidgets(
      'Async methods with and without error work',
      (tester) async {
        final modelRM = ReactiveModel.create(0);
        int onData;

        final widget = StateBuilder(
          observeMany: [() => modelRM],
          builder: (_, __) {
            return modelRM.whenConnectionState(
              onIdle: () => _widgetBuilder('onIdle'),
              onWaiting: () => _widgetBuilder('onWaiting'),
              onData: (data) => _widgetBuilder('${data}'),
              onError: (error) => _widgetBuilder('${error.message}'),
            );
          },
        );
        await tester.pumpWidget(widget);
        expect(modelRM.isA<int>(), isTrue);

        expect(find.text(('onIdle')), findsOneWidget);

        //sync increment without error
        modelRM.setState((_) async {
          final model = Model();
          await model.incrementAsync();
          return model.counter;
        }, onData: (context, data) {
          onData = data;
        });
        await tester.pump();
        expect(find.text(('onWaiting')), findsOneWidget);
        expect(onData, isNull);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('1'), findsOneWidget);
        expect(onData, equals(1));

        //sync increment with error
        modelRM.setState(
          (_) async {
            final model = Model();
            await model.incrementAsyncError();
            return model.counter;
          },
          catchError: true,
        );
        await tester.pump();
        expect(find.text(('onWaiting')), findsOneWidget);

        await tester.pump(Duration(seconds: 1));
        expect(find.text('Error message'), findsOneWidget);
        expect(onData, equals(1));
      },
    );

    testWidgets(
      'ReactiveModel : join singleton to new reactive from setValue',
      (tester) async {
        final inject = Inject(() => Model());
        final modelRM0 = inject.getReactive();
        final modelRM1 = inject.getReactive(true);
        final modelRM2 = inject.getReactive(true);

        final widget = Column(
          children: <Widget>[
            StateBuilder(
              observeMany: [() => modelRM0],
              builder: (context, _) {
                return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
              },
            ),
            StateBuilder(
              observeMany: [() => modelRM1],
              builder: (context, _) {
                return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
              },
            ),
            StateBuilder(
              observeMany: [() => modelRM2],
              builder: (context, _) {
                return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
              },
            )
          ],
        );

        await tester.pumpWidget(widget);

        //mutate reactive instance 1
        modelRM1.setState(
          (_) => modelRM1.state..incrementError(),
          joinSingleton: true,
          catchError: true,
        );
        await tester.pump();
        expect(find.text('modelRM0-0'), findsOneWidget);
        expect(find.text('modelRM1-0'), findsOneWidget);
        expect(find.text('modelRM2-0'), findsOneWidget);
        expect(modelRM0.hasError, isTrue);
        expect(modelRM1.hasError, isTrue);
        expect(modelRM2.isIdle, isTrue);

        //mutate reactive instance 2
        modelRM2.setState(
          (_) => modelRM2.state..incrementError(),
          joinSingleton: true,
          catchError: true,
        );
        await tester.pump();
        expect(find.text('modelRM0-0'), findsOneWidget);
        expect(find.text('modelRM1-0'), findsOneWidget);
        expect(find.text('modelRM2-0'), findsOneWidget);
        expect(modelRM0.hasError, isTrue);
        expect(modelRM1.hasError, isTrue);
        expect(modelRM2.hasError, isTrue);

        //mutate reactive instance 1
        modelRM1.setState((_) {
          modelRM1.state.increment();
          return Model()..counter = modelRM1.state.counter;
        }, joinSingleton: true);
        await tester.pump();
        expect(find.text('modelRM0-1'), findsOneWidget);
        expect(find.text('modelRM1-1'), findsOneWidget);
        expect(find.text('modelRM2-0'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);
        expect(modelRM1.hasData, isTrue);
        expect(modelRM2.hasError, isTrue);

        //mutate reactive instance 2
        modelRM2.setState((_) {
          modelRM2.state.increment();
          return Model()..counter = modelRM2.state.counter;
        }, joinSingleton: true);
        await tester.pump();
        expect(find.text('modelRM0-2'), findsOneWidget);
        expect(find.text('modelRM1-1'), findsOneWidget);
        expect(find.text('modelRM2-2'), findsOneWidget);
        expect(modelRM0.hasData, isTrue);
        expect(modelRM1.hasData, isTrue);
        expect(modelRM2.hasData, isTrue);
      },
    );
  });

  test(
      'ReactiveModel: get new reactive model with the same seed returns the same instance',
      () {
    //get new reactive instance with the default seed
    final modelNewRM1 = modelRM.asNew();

    expect(modelNewRM1, isA<ReactiveModel>());
    expect(modelRM != modelNewRM1, isTrue);
    ////get another new reactive instance with the default seed
    final modelNewRM2 = modelRM.asNew();
    expect(modelNewRM2, isA<ReactiveModel>());
    expect(modelNewRM2 == modelNewRM1, isTrue);

    //get new reactive instance with the custom seed
    final modelNewRM3 = modelRM.asNew(Seeds.seed1);

    expect(modelNewRM3, isA<ReactiveModel>());
    expect(modelNewRM3 != modelNewRM1, isTrue);
    ////get another new reactive instance with the default seed
    final modelNewRM4 = modelRM.asNew(Seeds.seed1);
    expect(modelNewRM4, isA<ReactiveModel>());
    expect(modelNewRM4 == modelNewRM3, isTrue);
  });

  test('ReactiveModel: get new reactive instance always return', () {
    final modelNewRM1 = modelRM.asNew();
    final modelNewRM2 = modelNewRM1.asNew();
    expect(modelNewRM1 == modelNewRM2, isTrue);
  });

  test('ReactiveModel: ReactiveModel.create works ', () {
    final _modelRM = ReactiveModel.create(1)..listenToRM((rm) {});
    expect(_modelRM, isA<ReactiveModel>());
    _modelRM.setState((_) => _modelRM.state + 1);
    expect(_modelRM.state, equals(2));
  });

  testWidgets(
    'ReactiveModel : reactive singleton and reactive instances work with seed',
    (tester) async {
      final inject = Inject(() => Model());
      final modelRM0 = inject.getReactive();
      final modelRM1 = modelRM0.asNew(Seeds.seed1);
      final modelRM2 = modelRM1.asNew(Seeds.seed2);

      final widget = Column(
        children: <Widget>[
          StateBuilder(
            observeMany: [() => modelRM0],
            builder: (context, _) {
              return _widgetBuilder('modelRM0-${modelRM0.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM1],
            builder: (context, _) {
              return _widgetBuilder('modelRM1-${modelRM1.state.counter}');
            },
          ),
          StateBuilder(
            observeMany: [() => modelRM2],
            builder: (context, _) {
              return _widgetBuilder('modelRM2-${modelRM2.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);

      //
      modelRM0.setState((s) => s.increment(), seeds: [Seeds.seed1]);
      await tester.pump();
      expect(find.text('modelRM0-1'), findsOneWidget);
      expect(find.text('modelRM1-1'), findsOneWidget);
      expect(find.text('modelRM2-0'), findsOneWidget);

      //
      modelRM0.setState((s) => s.increment(),
          seeds: [Seeds.seed1, Seeds.seed2, 'nonExistingSeed']);
      await tester.pump();
      expect(find.text('modelRM0-2'), findsOneWidget);
      expect(find.text('modelRM1-2'), findsOneWidget);
      expect(find.text('modelRM2-2'), findsOneWidget);

      //
      modelRM0.setState((s) => s.increment(), notifyAllReactiveInstances: true);
      await tester.pump();
      expect(find.text('modelRM0-3'), findsOneWidget);
      expect(find.text('modelRM1-3'), findsOneWidget);
      expect(find.text('modelRM2-3'), findsOneWidget);
    },
  );

  test('ReactiveStatesRebuilder throws if inject is null ', () {
    expect(() => ReactiveModelImp(null), throwsAssertionError);
  });

  testWidgets(
    'ReactiveModel: issue #49 reset to Idle after error or data',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return _widgetBuilder(
            '${modelRM.state.counter}',
            '${modelRM.error?.message}',
          );
        },
      );
      await tester.pumpWidget(widget);
      expect(find.text(('error message')), findsNothing);
      //
      modelRM.setState((s) => s.incrementError(), catchError: true);
      await tester.pump();
      expect(find.text(('error message')), findsOneWidget);
      expect(modelRM.isIdle, isFalse);
      expect(modelRM.hasError, isTrue);
      expect(modelRM.hasData, isFalse);
      //reset to Idle
      modelRM.resetToIdle();
      modelRM.rebuildStates();
      await tester.pump();
      expect(modelRM.isIdle, isTrue);
      expect(modelRM.hasError, isFalse);
      expect(modelRM.hasData, isFalse);
      expect(find.text(('error message')), findsNothing);
    },
  );

  testWidgets(
    'ReactiveModel: reset to hasData',
    (tester) async {
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return _widgetBuilder(
            '${modelRM.state.counter}',
            '${modelRM.error?.message}',
          );
        },
      );
      await tester.pumpWidget(widget);
      expect(find.text(('error message')), findsNothing);
      //
      modelRM.setState((s) => s.incrementError(), catchError: true);
      await tester.pump();
      expect(find.text(('error message')), findsOneWidget);
      expect(modelRM.isIdle, isFalse);
      expect(modelRM.hasError, isTrue);
      expect(modelRM.hasData, isFalse);
      //reset to Idle
      modelRM.resetToHasData();
      modelRM.rebuildStates();
      await tester.pump();
      expect(modelRM.isIdle, isFalse);
      expect(modelRM.hasError, isFalse);
      expect(modelRM.hasData, isTrue);
      expect(find.text(('error message')), findsNothing);
    },
  );

  testWidgets(
    'issue #55: should reset value to null after error',
    (tester) async {
      final modelRM = ReactiveModel.create(0);
      int numberOfRebuild = 0;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        tag: 'tag1',
        builder: (_, __) {
          return _widgetBuilder('${++numberOfRebuild}');
        },
      );
      await tester.pumpWidget(widget);
      //one rebuild
      expect(find.text(('1')), findsOneWidget);

      modelRM.setState((_) => modelRM.state + 1);
      await tester.pump();
      //two rebuilds
      expect(find.text(('2')), findsOneWidget);

      modelRM.setState(
        (_) => throw Exception(),
        catchError: true,
      );
      await tester.pump();
      //three rebuilds
      expect(find.text(('3')), findsOneWidget);

      modelRM.setState((_) => modelRM.state);
      await tester.pump();
      //four rebuilds
      expect(find.text(('4')), findsOneWidget);
    },
  );

  testWidgets(
    'testing toString override',
    (tester) async {
      final modelRM = ReactiveModel.create(Model())..listenToRM((rm) {});
      //
      expect(modelRM.toString(), contains('<Model> RM'));
      expect(modelRM.toString(), contains(' | isIdle'));
      //
      modelRM.setState((s) => s.incrementAsync());

      expect(modelRM.toString(), contains(' | isWaiting'));
      await tester.pump(Duration(seconds: 1));
      expect(modelRM.toString(), contains(" | hasData : (Counter(1))"));

      //
      modelRM.setState((s) => s.incrementAsyncError());
      await tester.pump(Duration(seconds: 1));
      expect(modelRM.toString(),
          contains(' | hasError : (Exception: Error message)'));

      //
      expect('${modelRM.asNew('seed1')}',
          contains('<Model> RM (new seed: "seed1")'));
      expect('${modelRM.asNew('seed1')}', contains(' | isIdle'));

      final intStream = ReactiveModel.stream(getStream());
      expect(intStream.toString(), contains('Stream of <int> RM'));
      expect(intStream.toString(), contains('| isWaiting'));
      await tester.pump(Duration(seconds: 3));
      expect(intStream.toString(), contains('| hasData : (2)'));

      final intFuture = ReactiveModel.future(getFuture()).asNew();
      expect(intFuture.toString(),
          contains('Future of <int> RM (new seed: "defaultReactiveSeed")'));
      expect(intFuture.toString(), contains('| isWaiting'));
      await tester.pump(Duration(seconds: 3));
      expect(intFuture.toString(), contains('| hasData : (1)'));
    },
  );

  testWidgets(
    'ReactiveModel : global ReactiveModel error handling',
    (tester) async {
      ReactiveModel<Model> modelRM = RM.create(Model());
      String errorMessage;
      final widget = Column(
        children: <Widget>[
          StateBuilder<Model>(
            observe: () => modelRM
              ..onError((context, error) {
                errorMessage = error.message;
              }),
            builder: (context, modelRM) {
              return _widgetBuilder('${modelRM.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);
      modelRM.setState((s) => s.incrementAsyncError());
      expect(find.text('0'), findsOneWidget);
      expect(modelRM.isWaiting, isTrue);
      expect(errorMessage, isNull);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('0'), findsOneWidget);
      expect(modelRM.hasError, isTrue);
      expect(errorMessage, 'Error message');
    },
  );

  testWidgets(
    'ReactiveModel : error from setState is prioritized on the  global ReactiveModel error',
    (tester) async {
      ReactiveModel<Model> modelRM = RM.create(Model());
      String globalErrorMessage;
      String setStateErrorMessage;
      final widget = Column(
        children: <Widget>[
          StateBuilder<Model>(
            observe: () => modelRM
              ..onError((context, error) {
                globalErrorMessage = error.message;
              }),
            builder: (context, modelRM) {
              return _widgetBuilder('${modelRM.state.counter}');
            },
          )
        ],
      );

      await tester.pumpWidget(widget);
      modelRM.setState(
        (s) => s.incrementAsyncError(),
        onError: (_, error) {
          setStateErrorMessage = error.message;
        },
      );
      expect(find.text('0'), findsOneWidget);
      expect(modelRM.isWaiting, isTrue);

      await tester.pump(Duration(seconds: 1));
      expect(find.text('0'), findsOneWidget);
      expect(modelRM.hasError, isTrue);
      expect(setStateErrorMessage, 'Error message');
      expect(globalErrorMessage, isNull);
    },
  );

  testWidgets(
    'issue #78: global ReactiveModel onData',
    (tester) async {
      int onDataFromSetState;
      int onDataGlobal;
      final widget = StateBuilder(
        observeMany: [() => modelRM],
        builder: (_, __) {
          return Container();
        },
      );
      await tester.pumpWidget(widget);

      modelRM.onData((data) {
        onDataGlobal = data.counter;
      });
      //
      expect(onDataFromSetState, null);
      expect(onDataGlobal, null);
      modelRM.setState(
        (s) => s.increment(),
        onData: (context, data) {
          onDataFromSetState = data.counter;
        },
      );

      await tester.pump();
      expect(onDataFromSetState, 1);
      expect(onDataGlobal, 1);
    },
  );

  test('listen to RM and unsubscribe', () {
    final rm = RM.create(0);
    int data;
    final unsubscribe = rm.listenToRM((rm) {
      data = rm.state;
    });
    expect(data, isNull);
    expect(rm.observers().length, 1);
    rm.state++;
    expect(data, 1);
    unsubscribe();
    expect(rm.observers().length, 0);
  });
}

class Model {
  int counter = 0;

  void increment() {
    counter++;
  }

  void incrementError() {
    throw Exception('error message');
  }

  Future<void> incrementAsync() async {
    await getFuture();
    counter++;
  }

  Future<void> incrementAsyncError() async {
    await getFuture();
    throw Exception('Error message');
  }

  Stream<int> incrementStream() async* {
    await Future.delayed(Duration(seconds: 1));
    yield ++counter;
    await Future.delayed(Duration(seconds: 1));
    yield ++counter;
    await Future.delayed(Duration(seconds: 1));
    yield --counter;
    throw Exception('Error message');
  }

  @override
  String toString() {
    return 'Counter($counter)';
  }
}

class ImmutableModel {
  final int counter;

  ImmutableModel(this.counter);

  Stream<ImmutableModel> incrementStream() async* {
    await Future.delayed(Duration(seconds: 1));
    yield ImmutableModel(counter + 1);
    await Future.delayed(Duration(seconds: 1));
    yield ImmutableModel(counter + 2);
    await Future.delayed(Duration(seconds: 1));
    yield this;
    throw Exception('Error message');
  }
}

Widget _widgetBuilder(String text1, [String text2, String text3]) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: <Widget>[
        Text(text1 ?? ''),
        Text(text2 ?? ''),
        Text(text3 ?? ''),
      ],
    ),
  );
}

Future<int> getFuture() => Future.delayed(Duration(seconds: 1), () => 1);
Future<int> getFutureWithError() => Future.delayed(Duration(seconds: 1), () {
      throw Exception('error message');
    });
Stream<int> getStream() =>
    Stream.periodic(Duration(seconds: 1), (num) => num).take(3);

enum Seeds { seed1, seed2 }
