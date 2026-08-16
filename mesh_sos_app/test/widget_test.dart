import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_sos_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeshSosAppRoot());
    expect(find.text('Offline Mesh SOS'), findsOneWidget);
  });
}
