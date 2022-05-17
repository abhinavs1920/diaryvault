import 'package:bloc/bloc.dart';
import 'package:dairy_app/features/notes/core/failures/failure.dart';
import 'package:dairy_app/features/notes/data/models/notes_model.dart';
import 'package:dairy_app/features/notes/domain/entities/notes.dart';
import 'package:dairy_app/features/notes/domain/repositories/notes_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

part 'notes_event.dart';
part 'notes_state.dart';

class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final INotesRepository notesRepository;

  NotesBloc({required this.notesRepository})
      : super(const NoteDummyState(id: "")) {
    on<InitializeNote>((event, emit) async {
      // if id is present, create a new note else fetch the existing note from database

      if (event.id == null) {
        var _id = _generateUniqueId();
        QuillController _controller = QuillController(
            document: Document()..insert(0, ''),
            selection: const TextSelection.collapsed(offset: 0));

        emit(
          NoteInitialState(
            newNote: true,
            id: _id,
            title: "",
            createdAt: DateTime.now(),
            controller: _controller,
          ),
        );
        return;
      }

      emit(const NoteFetchLoading(id: ""));
      var result = await notesRepository.getNote(event.id!);

      result.fold(
        (error) {
          emit(const NoteFetchFailed(id: ""));
        },
        (note) {
          final _doc = Document.fromJson(jsonDecode(note.body));
          QuillController _controller = QuillController(
            document: _doc,
            selection: const TextSelection.collapsed(offset: 0),
          );

          emit(NoteInitialState(
            id: event.id!,
            newNote: false,
            title: "",
            createdAt: DateTime.now(),
            controller: _controller,
          ));
        },
      );
    });

    on<UpdateNote>((event, emit) {
      // we don't want to update when something is getting saved or deleted
      if (state is NoteInitialState || state is NoteUpdatedState) {
        // TODO: need to handle asset dependecies more clearly, there is no callback for asset removal
        // so we need to process the body afterwards to get current list of assets, and suitably delete removed ones
        emit(NoteUpdatedState(
          newNote: state.newNote!,
          id: state.id,
          title: event.title ?? state.title!,
          controller: state.controller!,
          createdAt: state.createdAt!,
        ));
      }
    });

    on<SaveNote>((event, emit) async {
      // TODO: can add some validation like title and body can't be empty
      emit(NoteSaveLoading(
        newNote: state.newNote!,
        id: state.id,
        title: state.title!,
        controller: state.controller!,
        createdAt: state.createdAt!,
      ));

      var _body = state.controller!.document.toDelta().toJson().toString();
      var _plainText = state.controller!.document.toPlainText();

      var _hash =
          _generateHash(state.title! + state.createdAt.toString() + _body);

      var note = Note(
        id: state.id,
        createdAt: state.createdAt!,
        title: state.title!,
        body: _body,
        hash: _hash,
        lastModified: DateTime.now(),
        plainText: _plainText,
        assetDependencies: [],
        deleted: false,
      );

      Either<NotesFailure, void> result;

      if (state.newNote!) {
        result = await notesRepository.saveNote(note as NoteModel);
      } else {
        result = await notesRepository.updateNote(note as NoteModel);
      }
      result.fold((error) {
        emit(NotesSavingFailed(
          newNote: state.newNote!,
          id: state.id,
          title: state.title!,
          controller: state.controller!,
          createdAt: state.createdAt!,
        ));
      }, (_) {
        emit(NoteSavedSuccesfully(
          newNote: state.newNote!,
          id: state.id,
          title: state.title!,
          controller: state.controller!,
          createdAt: state.createdAt!,
        ));
      });
    });
  }

  // helper methods
  String _generateUniqueId() {
    var uuid = const Uuid();
    return uuid.v1();
  }

  String _generateHash(String text) {
    var bytes = utf8.encode(text);
    var digest = sha1.convert(bytes);
    return digest.toString();
  }
}
