import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../planning/widgets/planning_widgets.dart';
import '../models/maintenance_record.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';

/// Create + edit a [MaintenanceRecord] — dual-purpose like
/// `NewProposalScreen`/`NewReportScreen`. When [reportId] (or [record] with
/// a linked report) is set, the linked report is shown read-only and saving
/// drives its status forward (see `AdminFeedbackViewModel`/
/// `FeedbackAdminRepository`). See MODULE3_ADMIN_IMPLEMENTATION_PLAN.md
/// §6.6.
class NewMaintenanceRecordScreen extends StatefulWidget {
  const NewMaintenanceRecordScreen({
    super.key,
    this.record,
    this.reportId,
    this.stationId,
    this.reportSummary,
  });

  final MaintenanceRecord? record;
  final String? reportId;
  final String? stationId;

  /// Read-only label for the linked report shown at the top of the form
  /// (e.g. "Broken Connector · IOI City Mall") when creating a new record
  /// from `AdminReportDetailsScreen`.
  final String? reportSummary;

  bool get _editing => record != null;

  @override
  State<NewMaintenanceRecordScreen> createState() =>
      _NewMaintenanceRecordScreenState();
}

class _NewMaintenanceRecordScreenState
    extends State<NewMaintenanceRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _summaryController = TextEditingController(
    text: widget.record?.summary ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.record?.description ?? '',
  );
  late final _technicianController = TextEditingController(
    text: widget.record?.technicianName ?? '',
  );
  late final _etaController = TextEditingController(
    text: widget.record?.etaLabel ?? '',
  );
  late final _costController = TextEditingController(
    text: widget.record?.cost == null ? '' : widget.record!.cost.toString(),
  );
  late String _status = widget.record?.status ?? 'Scheduled';
  late DateTime _maintenanceDate =
      widget.record?.maintenanceDate ?? DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    _technicianController.dispose();
    _etaController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _maintenanceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _maintenanceDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final vm = context.read<AdminFeedbackViewModel>();
    final cost = double.tryParse(_costController.text.trim());
    try {
      if (widget._editing) {
        await vm.updateMaintenanceRecord(
          widget.record!,
          summary: _summaryController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          maintenanceDate: _maintenanceDate,
          technicianName: _technicianController.text.trim().isEmpty
              ? null
              : _technicianController.text.trim(),
          etaLabel:
              _etaController.text.trim().isEmpty ? null : _etaController.text.trim(),
          cost: cost,
        );
      } else {
        await vm.createMaintenanceRecord(
          summary: _summaryController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          maintenanceDate: _maintenanceDate,
          reportId: widget.reportId,
          stationId: widget.stationId,
          technicianName: _technicianController.text.trim().isEmpty
              ? null
              : _technicianController.text.trim(),
          etaLabel:
              _etaController.text.trim().isEmpty ? null : _etaController.text.trim(),
          cost: cost,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget._editing ? 'Maintenance record updated.' : 'Maintenance record logged.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Maintenance record save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save the maintenance record. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text('Delete Record?'),
        content: const Text(
          'This maintenance record will be removed permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await context
          .read<AdminFeedbackViewModel>()
          .deleteMaintenanceRecord(widget.record!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Maintenance record delete failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget._editing ? 'Edit Maintenance Record' : 'Log Maintenance Record',
            style: planningAppBarTitleStyle,
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            if (widget._editing)
              IconButton(
                onPressed: _submitting ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete record',
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: planningPagePadding,
              children: [
                if (widget.reportSummary != null) ...[
                  AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Linked report: ${widget.reportSummary}',
                            style: const TextStyle(
                              color: planningTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  planningSectionGap,
                ],
                TextFormField(
                  controller: _summaryController,
                  decoration: const InputDecoration(
                    labelText: 'Summary',
                    hintText: 'e.g. Replaced Type 2 connector',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Summary is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _technicianController,
                  decoration: const InputDecoration(
                    labelText: 'Technician name',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final status in kMaintenanceStatuses)
                      DropdownMenuItem(value: status, child: Text(status)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _etaController,
                  decoration: InputDecoration(
                    labelText: _status == 'Delayed' ? 'Delayed by' : 'ETA',
                    hintText: 'e.g. 1 hour, 30 mins',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Maintenance date',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      '${_maintenanceDate.day}/${_maintenanceDate.month}/${_maintenanceDate.year}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cost (RM)',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget._editing ? 'Save Changes' : 'Log Maintenance'),
                ),
              ],
            ),
          ),
        ),
      );
}
