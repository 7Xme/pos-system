import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosBloc', () {
    test('يضيف صنفاً للسلة عبر الباركود', () async {
      final bloc = PosBloc(
        repo: DemoCatalogRepository(),
        checkoutRepo: DemoCheckoutRepository(),
      );
      bloc.add(PosStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>((s) => s.status == PosStatus.ready),
        ),
      );
      bloc.add(const PosBarcodeScanned('100001'));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>((s) => s.cart.length == 1),
        ),
      );
      expect(bloc.state.total, 25);
      await bloc.close();
    });

    test('إتمام البيع يصفّر السلة ويصدر رقم فاتورة', () async {
      final bloc = PosBloc(
        repo: DemoCatalogRepository(),
        checkoutRepo: DemoCheckoutRepository(),
      );
      bloc.add(PosStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>((s) => s.status == PosStatus.ready),
        ),
      );
      bloc.add(const PosBarcodeScanned('100002'));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>((s) => s.cart.isNotEmpty),
        ),
      );
      bloc.add(PosCheckout(bloc.state.total));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>(
            (s) =>
                s.status == PosStatus.checkoutSuccess &&
                s.lastInvoiceNumber != null &&
                s.cart.isEmpty,
          ),
        ),
      );
      await bloc.close();
    });
  });
}
