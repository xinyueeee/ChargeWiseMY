import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/planning_widgets.dart';
import '../services/admin_planning_assistant_service.dart';
import '../viewmodels/admin_planning_viewmodel.dart';

class AdminPlanningAssistantScreen extends StatefulWidget {
  const AdminPlanningAssistantScreen({
    super.key,
    required this.proposalId,
  });

  final String proposalId;

  @override
  State<AdminPlanningAssistantScreen> createState() =>
      _AdminPlanningAssistantScreenState();
}

class _AdminPlanningAssistantScreenState
    extends State<AdminPlanningAssistantScreen> {
  static const _suggestions = [
    'Why recommended?',
    'Main risks',
    'Infrastructure coverage',
    'Coverage-gap relationship',
    'Community response',
    'Nearby proposals',
    'What should I verify?',
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AdminAssistantMessage> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const AdminAssistantMessage(
        text:
            'I’m the grounded local Planning Assistant fallback. No external AI service is connected. I use only the proposal, rule-based assessment, nearby infrastructure, current coverage-gap results, settlement context, and community support available in ChargeWise.',
        fromAdministrator: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminPlanningViewModel>();
    final proposal = viewModel.proposalById(widget.proposalId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          proposal?.city ?? 'Planning Assistant (Local)',
          overflow: TextOverflow.ellipsis,
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: proposal == null
          ? const PlanningEmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'Assistant unavailable',
              message: 'The selected proposal is no longer available.',
            )
          : SafeArea(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFF4FAF8),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.offline_bolt_outlined,
                                size: 16, color: green),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Grounded local fallback · no external AI call',
                                style: TextStyle(
                                  color: green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Suggested questions',
                          style: TextStyle(
                            color: planningMutedTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final suggestion in _suggestions) ...[
                                ActionChip(
                                  label: Text(suggestion),
                                  onPressed: _sending
                                      ? null
                                      : () => _send(
                                            viewModel,
                                            proposal.id,
                                            suggestion,
                                          ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: _sending
                                  ? null
                                  : (value) => _send(
                                        viewModel,
                                        proposal.id,
                                        value,
                                      ),
                              decoration: const InputDecoration(
                                hintText: 'Ask about this proposal',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            tooltip: 'Send question',
                            onPressed: _sending
                                ? null
                                : () => _send(
                                      viewModel,
                                      proposal.id,
                                      _controller.text,
                                    ),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _send(
    AdminPlanningViewModel viewModel,
    String proposalId,
    String question,
  ) async {
    final normalized = question.trim();
    if (normalized.isEmpty || _sending) return;
    final proposal = viewModel.proposalById(proposalId);
    if (proposal == null) return;
    _controller.clear();
    setState(() {
      _messages.add(
        AdminAssistantMessage(
          text: normalized,
          fromAdministrator: true,
        ),
      );
      _sending = true;
    });
    _scrollToEnd();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final answer = viewModel.answerAssistantQuestion(
      question: normalized,
      proposal: proposal,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        AdminAssistantMessage(
          text: answer,
          fromAdministrator: false,
        ),
      );
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AdminAssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final fromAdmin = message.fromAdministrator;
    return Align(
      alignment: fromAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: fromAdmin ? green : const Color(0xFFF0F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: fromAdmin ? Colors.white : planningTextColor,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
