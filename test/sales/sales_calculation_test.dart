import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

void main() {
  group('Invoice & Line Items Arithmetic Tests (Strict Fixed-Point)', () {
    test('Calculates line item totals with zero tax accurately', () {
      // 3 items @ 10.00 SAR = 30.00 SAR gross
      // No tax. Total = 30.00 SAR (3000 raw units)
      final line1 = InvoiceItemModel.create(
        itemId: 1,
        quantity: 3,
        unitPrice: const Money(1000), // 10.00 SAR
      );

      expect(line1.quantity, 3);
      expect(line1.unitPrice, const Money(1000));
      expect(line1.taxAmount, Money.zero);
      expect(line1.totalPrice, const Money(3000));
    });

    test('Calculates line item with discount without tax', () {
      // 2 items @ 50.00 SAR = 100.00 SAR
      // Discount = 10.00 SAR (1000 raw units)
      // Net = 90.00 SAR
      // Total = 90.00 SAR (9000 raw units)
      final line = InvoiceItemModel.create(
        itemId: 2,
        quantity: 2,
        unitPrice: const Money(5000),
        discount: const Money(1000),
      );

      expect(line.discount, const Money(1000));
      expect(line.taxAmount, Money.zero);
      expect(line.totalPrice, const Money(9000));
    });

    test(
      'Aggregates multi-line invoice with additional discount and cash payment',
      () {
        final now = DateTime.now();
        final line1 = InvoiceItemModel.create(
          itemId: 1,
          quantity: 2,
          unitPrice: const Money(2000), // 40.00 SAR
        );
        final line2 = InvoiceItemModel.create(
          itemId: 2,
          quantity: 1,
          unitPrice: const Money(10000), // 100.00 SAR
        );

        // Subtotal = 140.00 SAR
        // Discount = 10.00 SAR
        // Total = 130.00 SAR
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-2026-0001',
          partyId: 10,
          invoiceType: InvoiceType.sale,
          items: [line1, line2],
          additionalDiscount: const Money(1000), // 10.00 SAR
          paidAmount: const Money(13000), // Fully paid cash
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        expect(invoice.subtotal, const Money(14000));
        expect(invoice.discount, const Money(1000));
        expect(invoice.tax, Money.zero);
        expect(invoice.total, const Money(13000));
        expect(invoice.paidAmount, const Money(13000));
        expect(invoice.remainingAmount, Money.zero);
        expect(invoice.isFullyPaid, isTrue);
      },
    );

    test('Credit invoice leaves remaining balance equal to total', () {
      final now = DateTime.now();
      final line = InvoiceItemModel.create(
        itemId: 1,
        quantity: 1,
        unitPrice: const Money(20000), // 200.00 (no VAT)
      );

      final invoice = InvoiceModel.buildWithItems(
        invoiceNumber: 'INV-2026-0002',
        partyId: 5,
        invoiceType: InvoiceType.sale,
        paymentType: PaymentType.credit,
        items: [line],
        paidAmount: Money.zero,
        invoiceDate: now,
        createdAt: now,
        updatedAt: now,
      );

      expect(invoice.total, const Money(20000));
      expect(invoice.paidAmount, Money.zero);
      expect(invoice.remainingAmount, const Money(20000));
      expect(invoice.isUnpaid, isTrue);
    });
  });

  group('Invoice Posting Engine Logic (Stock & Customer/Supplier Ledger)', () {
    late FakeInvoicesRepository invoicesRepo;

    setUp(() {
      invoicesRepo = FakeInvoicesRepository();
      // Setup sample item: initial stock = 100
      invoicesRepo.inMemoryItems[1] = ItemModel(
        id: 1,
        code: 'MILK01',
        name: 'حليب المراعي 1 لتر',
        costPrice: const Money(400),
        sellingPrice: const Money(600),
        stockQuantity: 100,
        minAlertLimit: 10,
        unitId: 1,
        categoryId: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Setup sample customer: initial balance = 0
      invoicesRepo.inMemoryParties[1] = PartyModel(
        id: 1,
        name: 'عميل تجريبي',
        phone: '0501112233',
        type: PartyType.customer,
        currentBalance: Money.zero,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Setup sample supplier: initial balance = 0
      invoicesRepo.inMemoryParties[2] = PartyModel(
        id: 2,
        name: 'مورد تجريبي',
        phone: '0504445566',
        type: PartyType.supplier,
        currentBalance: Money.zero,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test(
      'Finalizing a Credit Sale Invoice deducts stock and increases customer debt (balance decreases)',
      () async {
        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: 1,
          quantity: 10,
          unitPrice: const Money(600), // 60.00 (no VAT)
        );

        final inv = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-2026-0010',
          partyId: 1,
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final invId = await invoicesRepo.createInvoice(inv);
        await invoicesRepo.finalizeInvoice(invId);

        // 1. Check item stock reduced by 10 (100 - 10 = 90)
        expect(invoicesRepo.inMemoryItems[1]?.stockQuantity, 90);

        // 2. Check customer owes remainingAmount (currentBalance becomes -60.00 SAR)
        expect(
          invoicesRepo.inMemoryParties[1]?.currentBalance,
          const Money(-6000),
        );

        // 3. Invoice status changed to approved
        final saved = await invoicesRepo.getInvoiceById(invId);
        expect(saved?.status, InvoiceStatus.approved);
      },
    );

    test(
      'Finalizing a Credit Purchase Invoice adds to stock and increases supplier credit (balance increases)',
      () async {
        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: 1,
          quantity: 50,
          unitPrice: const Money(400), // 200.00 (no VAT)
        );

        final inv = InvoiceModel.buildWithItems(
          invoiceNumber: 'PUR-2026-0001',
          partyId: 2,
          invoiceType: InvoiceType.purchase,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final invId = await invoicesRepo.createInvoice(inv);
        await invoicesRepo.finalizeInvoice(invId);

        // 1. Stock increased by 50 (100 + 50 = 150)
        expect(invoicesRepo.inMemoryItems[1]?.stockQuantity, 150);

        // 2. We owe supplier remainingAmount (currentBalance becomes +200.00 SAR)
        expect(
          invoicesRepo.inMemoryParties[2]?.currentBalance,
          const Money(20000),
        );
      },
    );

    test(
      'Finalizing a Sale Return increases stock and reduces customer debt',
      () async {
        // Customer starts with debt of -100.00 SAR
        invoicesRepo.inMemoryParties[1] = invoicesRepo.inMemoryParties[1]!
            .copyWith(currentBalance: const Money(-10000));

        final line = InvoiceItemModel.create(
          itemId: 1,
          quantity: 5,
          unitPrice: const Money(600), // 30.00 (no VAT)
        );

        final inv = InvoiceModel.buildWithItems(
          invoiceNumber: 'SRT-2026-0001',
          partyId: 1,
          invoiceType: InvoiceType.saleReturn,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero,
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.createInvoice(inv);
        await invoicesRepo.finalizeInvoice(invId);

        // 1. Stock returned (100 + 5 = 105)
        expect(invoicesRepo.inMemoryItems[1]?.stockQuantity, 105);

        // 2. Customer debt reduced: -10000 + 3000 = -7000 (-70.00 SAR)
        expect(
          invoicesRepo.inMemoryParties[1]?.currentBalance,
          const Money(-7000),
        );
      },
    );
  });

  group('Vouchers & Treasury Engine Logic', () {
    late FakeVouchersRepository vouchersRepo;

    setUp(() {
      vouchersRepo = FakeVouchersRepository();
      // Setup customer with initial debt of -500.00 SAR (-50000)
      vouchersRepo.inMemoryParties[1] = PartyModel(
        id: 1,
        name: 'عميل مدين',
        phone: '0501111111',
        type: PartyType.customer,
        currentBalance: const Money(-50000),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Setup supplier with initial credit of +1000.00 SAR (+100000)
      vouchersRepo.inMemoryParties[2] = PartyModel(
        id: 2,
        name: 'مورد دائن',
        phone: '0502222222',
        type: PartyType.supplier,
        currentBalance: const Money(100000),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test(
      'Receipt voucher (سند قبض) reduces customer debt and increases treasury cash',
      () async {
        final now = DateTime.now();
        final voucher = VoucherModel(
          voucherNumber: 'REC-2026-0001',
          voucherType: VoucherType.receipt,
          partyId: 1,
          amount: const Money(20000), // 200.00 SAR paid by customer
          paymentMethod: PaymentMethod.cash,
          statement: 'دفعة سداد حساب',
          voucherDate: now,
          createdAt: now,
        );

        await vouchersRepo.createVoucher(voucher);

        // Customer debt reduced from -500.00 to -300.00 SAR (-30000)
        expect(
          vouchersRepo.inMemoryParties[1]?.currentBalance,
          const Money(-30000),
        );

        // Treasury net balance is +200.00 SAR
        final treasury = await vouchersRepo.getTreasuryBalance();
        expect(treasury, const Money(20000));
      },
    );

    test(
      'Payment voucher (سند صرف) pays supplier and reduces treasury cash',
      () async {
        final now = DateTime.now();
        final voucher = VoucherModel(
          voucherNumber: 'PAY-2026-0001',
          voucherType: VoucherType.payment,
          partyId: 2,
          amount: const Money(40000), // 400.00 SAR paid to supplier
          paymentMethod: PaymentMethod.transfer,
          statement: 'سداد دفعة مورد',
          voucherDate: now,
          createdAt: now,
        );

        await vouchersRepo.createVoucher(voucher);

        // Supplier credit reduced from +1000.00 to +600.00 SAR (+60000)
        expect(
          vouchersRepo.inMemoryParties[2]?.currentBalance,
          const Money(60000),
        );

        // Treasury net balance is -400.00 SAR
        final treasury = await vouchersRepo.getTreasuryBalance();
        expect(treasury, const Money(-40000));
      },
    );

    test(
      'Deleting a voucher reverses the party balance and treasury impact',
      () async {
        final now = DateTime.now();
        final voucher = VoucherModel(
          voucherNumber: 'REC-2026-0002',
          voucherType: VoucherType.receipt,
          partyId: 1,
          amount: const Money(10000), // 100.00 SAR
          paymentMethod: PaymentMethod.cash,
          statement: 'دفعة خطأ',
          voucherDate: now,
          createdAt: now,
        );

        final id = await vouchersRepo.createVoucher(voucher);
        expect(
          vouchersRepo.inMemoryParties[1]?.currentBalance,
          const Money(-40000),
        );

        // Delete/cancel voucher
        await vouchersRepo.deleteVoucher(id);

        // Balance reverted back to -500.00 SAR (-50000)
        expect(
          vouchersRepo.inMemoryParties[1]?.currentBalance,
          const Money(-50000),
        );
        final treasury = await vouchersRepo.getTreasuryBalance();
        expect(treasury, Money.zero);
      },
    );
  });
}
