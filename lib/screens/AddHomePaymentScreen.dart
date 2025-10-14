import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/models/attachment_upload.dart';
import '../theme/app_theme.dart';

class AddHomePaymentScreen extends StatefulWidget {
  final String customerId;
  final String? customerName;
  const AddHomePaymentScreen({super.key, required this.customerId, this.customerName});

  @override
  State<AddHomePaymentScreen> createState() => _AddHomePaymentScreenState();
}

class _AddHomePaymentScreenState extends State<AddHomePaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  final List<AttachmentUpload> _attachments = [];
  bool _submitting = false;
  final List<String> _paymentTypes = const ['Cash', 'Bank', 'MobileMoney', 'Other'];
  String? _paymentType;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Payment${widget.customerName != null ? ' • ${widget.customerName}' : ''}')
            ,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amount,
                decoration: InputDecoration(
                  labelText: 'Amount (TZS)',
                  prefixIcon: const Icon(Icons.payments_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final d = double.tryParse((v ?? '').replaceAll(',', ''));
                  if (d == null || d <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                decoration: InputDecoration(
                  labelText: 'Reference (optional)\nBank ref or SMS code',
                  prefixIcon: const Icon(Icons.confirmation_number_rounded),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Payment Type',
                  prefixIcon: const Icon(Icons.category_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _paymentType,
                    hint: const Text('Select type (optional)'),
                    items: _paymentTypes
                        .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _paymentType = v),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _captureImage,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take Photo'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_rounded),
                    label: const Text('Add Image'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Add PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _attachments.isEmpty
                  ? const Text('No attachments added')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _attachments.map((a) {
                        final isImage = a.contentType.startsWith('image/');
                        return Stack(
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.shade200,
                              ),
                              child: isImage
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(a.bytes, fit: BoxFit.cover),
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                                          SizedBox(height: 4),
                                          Text('PDF', style: TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () => setState(() => _attachments.remove(a)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            )
                          ],
                        );
                      }).toList(),
                    ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(_submitting ? 'Submitting...' : 'Submit Payment for Approval'),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Note: A boss must approve this payment. You cannot approve your own entry.'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _attachments.add(AttachmentUpload(
        bytes: bytes,
        name: x.name,
        contentType: 'image/${x.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'}',
      ));
    });
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _attachments.add(AttachmentUpload(
        bytes: bytes,
        name: x.name,
        contentType: 'image/${x.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'}',
      ));
    });
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    setState(() {
      _attachments.add(AttachmentUpload(
        bytes: bytes,
        name: f.name,
        contentType: 'application/pdf',
      ));
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final amt = double.parse(_amount.text.replaceAll(',', ''));
      await HomeInternetService.addPayment(
        customerId: widget.customerId,
        amountPaid: amt,
        attachments: _attachments,
        reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        paymentType: _paymentType,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment submitted for approval')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
