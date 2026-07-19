import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Finds widgets that restate the `.panel` surface instead of reading
/// `core/chrome/panel.dart`'s tokens.
///
/// **Why this is an AST walk and not a grep.** `featured_gradient_test.dart`
/// guards its token with a plain substring search, and that works because its
/// two hex values are *distinctive* — nothing else in the app is that blue.
/// `.panel`'s four values are the opposite: `Radius.circular(16)` appears in
/// eight files and `EdgeInsets.all(14)` in three, because `.acard`, `.dcard`,
/// `.chcard` and the radar's `.chip` each share a number with `.panel` by
/// coincidence of the prototype rather than by being the same surface. A
/// file-level co-occurrence grep therefore false-positives immediately, most
/// loudly on `radar_view.dart`, which contains three of the four in widgets
/// that have nothing to do with each other.
///
/// So the honest question is not "does this *file* contain the four values?"
/// but "does one *widget*?", and the smallest thing in Dart that stands for a
/// widget is the declaration that builds it. That scoping is the only thing the
/// analyzer is here for — the values themselves are still compared as
/// normalised source, because the check runs on an unresolved parse (fast, no
/// build step, no `package_config` dance) and an unresolved `Palette.card` is
/// just an identifier either way.
///
/// The unit is the **outermost declaration that matches**: a build method, a
/// top-level widget-returning function, or a field initialiser. Once one
/// matches, its nested closures are not reported separately — they are the same
/// widget said twice.
List<PanelSurfaceCopy> findPanelSurfaceCopies(
  String source, {
  String path = '<source>',
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final _DeclarationScan scan = _DeclarationScan(path, result.lineInfo);
  result.unit.accept(scan);
  return scan.copies;
}

/// One declaration painting all four `.panel` values by hand.
class PanelSurfaceCopy {
  const PanelSurfaceCopy(this.path, this.line, this.declaration);

  final String path;
  final int line;

  /// The enclosing declaration, qualified by its class where it has one, so a
  /// failure names the widget rather than only the file.
  final String declaration;

  @override
  String toString() => '$path:$line — $declaration';
}

/// Visits every declaration and scans its whole subtree for the four values.
class _DeclarationScan extends RecursiveAstVisitor<void> {
  _DeclarationScan(this._path, this._lineInfo);

  final String _path;
  final LineInfo _lineInfo;
  final List<PanelSurfaceCopy> copies = <PanelSurfaceCopy>[];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_record(node, node.name.lexeme)) return;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_record(node, node.name.lexeme)) return;
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (_record(node, _variableNames(node.fields))) return;
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (_record(node, _variableNames(node.variables))) return;
    super.visitTopLevelVariableDeclaration(node);
  }

  /// Scans [node]'s subtree; records and returns `true` when all four values
  /// are present, which also stops the walk descending into it.
  bool _record(AstNode node, String name) {
    final _PanelValues values = _PanelValues();
    node.accept(values);
    if (!values.isPanelSurface) return false;

    copies.add(
      PanelSurfaceCopy(
        _path,
        _lineInfo.getLocation(node.offset).lineNumber,
        _qualify(node, name),
      ),
    );
    return true;
  }

  static String _variableNames(VariableDeclarationList list) =>
      list.variables.map((VariableDeclaration v) => v.name.lexeme).join(', ');

  /// `ClassName.member`, so `build` alone never has to identify a widget.
  /// Anything not in a class — a top-level function or variable — stands on its
  /// own name, which is already unique in its file.
  static String _qualify(AstNode node, String name) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is ClassDeclaration) return '${p.namePart.typeName.lexeme}.$name';
    }
    return name;
  }
}

/// Looks for `.panel`'s four values anywhere in one declaration's subtree.
///
/// Deliberately blind to the *container*. `.panel` reaches the screen as a
/// `DecoratedBox` in `panel.dart`, as an `Ink` in `games_hub.dart`, and the
/// near-misses reach it as `Material` + `RoundedRectangleBorder` — so a check
/// keyed on `BoxDecoration` would miss the copy most likely to be written,
/// which is a tappable one. Matching the values themselves catches every
/// spelling, including ones not invented yet.
class _PanelValues extends RecursiveAstVisitor<void> {
  bool fill = false;
  bool radius = false;
  bool border = false;
  bool padding = false;

  bool get isPanelSurface => fill && radius && border && padding;

  @override
  void visitNamedExpression(NamedExpression node) {
    // The fill has to be `Palette.card` *itself*. The radar's `.chip` and its
    // zoom buttons are `Palette.card.withValues(alpha: …)` and the sky
    // screen's is a ternary on selection — those are different surfaces that
    // happen to start from the same token, and reading them as a copy of
    // `.panel` would be wrong.
    if (node.name.label.name == 'color' &&
        _norm(node.expression.toSource()) == 'Palette.card') {
      fill = true;
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _inspect(node.toSource(), _callee(node), node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _inspect(node.toSource(), _callee(node), node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  void _inspect(String source, String callee, ArgumentList arguments) {
    final String normalised = _norm(source);

    // `BorderRadius.circular(16)` builds the same four corners as
    // `BorderRadius.all(Radius.circular(16))`, so both spellings count.
    if (normalised == 'Radius.circular(16)' ||
        normalised == 'BorderRadius.circular(16)') {
      radius = true;
    }

    if (normalised == 'EdgeInsets.all(14)') padding = true;

    // A hairline `--line` border, and only a fixed one. `.dcard`'s side colour
    // is a `switch` on the answer and `.chcard`'s is a local that follows it —
    // both stay out, because a border that changes is not this border.
    if ((callee == 'BorderSide' || callee == 'Border.all') &&
        _hasArgument(arguments, 'color', 'Palette.line')) {
      border = true;
    }
  }

  static bool _hasArgument(ArgumentList arguments, String name, String value) {
    return arguments.arguments.any(
      (Expression a) =>
          a is NamedExpression &&
          a.name.label.name == name &&
          _norm(a.expression.toSource()) == value,
    );
  }

  /// The constructor or static being called, `Target.member` where there is a
  /// target. An unresolved parse gives `Foo(...)` as a [MethodInvocation] and
  /// `const Foo(...)` as an [InstanceCreationExpression]; this flattens both.
  static String _callee(AstNode node) {
    if (node is MethodInvocation) {
      final String? target = node.target?.toSource();
      return target == null
          ? node.methodName.name
          : '$target.${node.methodName.name}';
    }
    if (node is InstanceCreationExpression) {
      return node.constructorName.toSource();
    }
    return '';
  }

  static String _norm(String source) =>
      source.replaceFirst(RegExp(r'^(const|new)\s+'), '');
}
