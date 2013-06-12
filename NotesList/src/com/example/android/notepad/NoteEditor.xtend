package com.example.android.notepad

import android.app.Activity
import android.content.AsyncQueryHandler
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.os.AsyncTask
import android.os.Bundle
import android.util.AttributeSet
import android.util.Log
import android.view.Menu
import android.view.MenuItem
import android.widget.EditText

/** 
 * Defines a custom EditText View that draws lines between each line of text that is displayed.
 */
class LinedEditText extends EditText {
	
	var Rect mRect
	var Paint mPaint

	new(Context context) {
		this(context, null)
	}
	
	new(Context context, AttributeSet attrs) {
		super(context, attrs);
		mRect = new Rect()
		mPaint = new Paint()
		mPaint.style = Paint.Style.STROKE
		mPaint.color = 0x800000FF
	}

	/** 
	 * This is called to draw the LinedEditText object
	 * @param canvas The canvas on which the background is drawn.
	 */
	protected override onDraw(Canvas canvas) {
		var count = lineCount
		var r = mRect
		var paint = mPaint
		for (i : 0 ..< count) {
			var baseline = getLineBounds(i, r)
			canvas.drawLine(r.left, baseline + 1, r.right, baseline + 1, paint)
		}
		super.onDraw(canvas)
	}
}

/** 
 * This Activity handles "editing" a note, where editing is responding to{@link Intent#ACTION_VIEW} (request to view data), edit a note{@link Intent#ACTION_EDIT}, create a note {@link Intent#ACTION_INSERT}, or
 * create a new note from the current contents of the clipboard {@link Intent#ACTION_PASTE}.
 * NOTE: Notice that the provider operations in this Activity are taking place on the UI thread.
 * This is not a good practice. It is only done here to make the code more readable. A real
 * application should use the {@link AsyncQueryHandler}or {@link AsyncTask} object to perform operations asynchronously on a separate thread.
 */
class NoteEditor extends Activity {
	static val TAG = 'NoteEditor'
	static val String[] PROJECTION = #{NotePad._ID, NotePad.COLUMN_NAME_TITLE, NotePad.COLUMN_NAME_NOTE}

	static val ORIGINAL_CONTENT = 'origContent'

	static val STATE_EDIT = 0

	static val STATE_INSERT = 1
	int mState
	Uri mUri
	Cursor mCursor
	EditText mText
	String mOriginalContent

	/** 
	 * This method is called by Android when the Activity is first started. From the incoming
	 * Intent, it determines what kind of editing is desired, and then does it.
	 */
	protected override onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState)
		val action = intent.action
		if (Intent.ACTION_EDIT == action) {
			mState = STATE_EDIT
			mUri = intent.data
		} else if (Intent.ACTION_INSERT == action || Intent.ACTION_PASTE == action) {
			mState = STATE_INSERT
			mUri = contentResolver.insert(intent.data, null)
			if (mUri === null) {
				Log.e(TAG, 'Failed to insert new note into ' + intent.data)
				finish
				return;
			}
			setResult(RESULT_OK, (new Intent()).action = mUri.toString)
		} else {
			Log.e(TAG, 'Unknown action, exiting')
			finish
			return;
		}
		mCursor = managedQuery(mUri, PROJECTION, null, null, null)
		if (Intent.ACTION_PASTE == action) {
			performPaste
			mState = STATE_EDIT
		}
		contentView = R.layout.note_editor
		mText = (findViewById(R.id.note) as EditText)
		if (savedInstanceState !== null) {
			mOriginalContent = savedInstanceState.getString(ORIGINAL_CONTENT)
		}
	}

	/** 
	 * This method is called when the Activity is about to come to the foreground. This happens
	 * when the Activity comes to the top of the task stack, OR when it is first starting.
	 * Moves to the first note in the list, sets an appropriate title for the action chosen by
	 * the user, puts the note contents into the TextView, and saves the original text as a
	 * backup.
	 */
	protected override onResume() {
		super.onResume()
		if (mCursor !== null) {
			mCursor.requery
			mCursor.moveToFirst
			if (mState === STATE_EDIT) {
				var colTitleIndex = mCursor.getColumnIndex(NotePad.COLUMN_NAME_TITLE)
				var title = mCursor.getString(colTitleIndex)
				var res = resources
				var text = String.format(res.getString(R.string.title_edit), title)
				title = text
			} else if (mState === STATE_INSERT) {
				title = getText(R.string.title_create)
			}
			var colNoteIndex = mCursor.getColumnIndex(NotePad.COLUMN_NAME_NOTE)
			var note = mCursor.getString(colNoteIndex)
			mText.textKeepState = note
			if (mOriginalContent === null) {
				mOriginalContent = note
			}
		} else {
			title = getText(R.string.error_title)
			mText.text = getText(R.string.error_message)
		}
	}

	/** 
	 * This method is called when an Activity loses focus during its normal operation, and is then
	 * later on killed. The Activity has a chance to save its state so that the system can restore
	 * it.
	 * Notice that this method isn't a normal part of the Activity lifecycle. It won't be called
	 * if the user simply navigates away from the Activity.
	 */
	protected override onSaveInstanceState(Bundle outState) {
		outState.putString(ORIGINAL_CONTENT, mOriginalContent)
	}

	/** 
	 * This method is called when the Activity loses focus.
	 * For Activity objects that edit information, onPause() may be the one place where changes are
	 * saved. The Android application model is predicated on the idea that "save" and "exit" aren't
	 * required actions. When users navigate away from an Activity, they shouldn't have to go back
	 * to it to complete their work. The act of going away should save everything and leave the
	 * Activity in a state where Android can destroy it if necessary.
	 * If the user hasn't done anything, then this deletes or clears out the note, otherwise it
	 * writes the user's work to the provider.
	 */
	protected override onPause() {
		super.onPause()
		if (mCursor !== null) {
			var text = mText.text.toString
			var length = text.length
			if (finishing && (length === 0)) {
				result = RESULT_CANCELED
				deleteNote
			} else if (mState === STATE_EDIT) {
				updateNote(text, null)
			} else if (mState === STATE_INSERT) {
				updateNote(text, text)
				mState = STATE_EDIT
			}
		}
	}

	/** 
	 * This method is called when the user clicks the device's Menu button the first time for
	 * this Activity. Android passes in a Menu object that is populated with items.
	 * Builds the menus for editing and inserting, and adds in alternative actions that
	 * registered themselves to handle the MIME types for this application.
	 * @param menu A Menu object to which items should be added.
	 * @return True to display the menu.
	 */
	override onCreateOptionsMenu(Menu menu) {
		var inflater = menuInflater
		inflater.inflate(R.menu.editor_options_menu, menu)
		if (mState === STATE_EDIT) {
			var intent = new Intent(null, mUri)
			intent.addCategory(Intent.CATEGORY_ALTERNATIVE)
			menu.addIntentOptions(Menu.CATEGORY_ALTERNATIVE, 0, 0, new ComponentName(this, typeof(NoteEditor)), null,
				intent, 0, null)
		}
		super.onCreateOptionsMenu(menu)
	}

	override onPrepareOptionsMenu(Menu menu) {
		var colNoteIndex = mCursor.getColumnIndex(NotePad.COLUMN_NAME_NOTE)
		var savedNote = mCursor.getString(colNoteIndex)
		var currentNote = mText.text.toString
		if (savedNote == currentNote) {
			menu.findItem(R.id.menu_revert).visible = false
		} else {
			menu.findItem(R.id.menu_revert).visible = true
		}
		super.onPrepareOptionsMenu(menu)
	}

	/** 
	 * This method is called when a menu item is selected. Android passes in the selected item.
	 * The switch statement in this method calls the appropriate method to perform the action the
	 * user chose.
	 * @param item The selected MenuItem
	 * @return True to indicate that the item was processed, and no further work is necessary. False
	 * to proceed to further processing as indicated in the MenuItem object.
	 */
	override onOptionsItemSelected(MenuItem item) {
		switch (item.itemId) {
			case R.id.menu_save: {
				var text = mText.text.toString
				updateNote(text, null)
				finish
			}
			case R.id.menu_delete: {
				deleteNote
				finish
			}
			case R.id.menu_revert:
				cancelNote
		}
		super.onOptionsItemSelected(item)
	}

	/** 
	 * A helper method that replaces the note's data with the contents of the clipboard.
	 */
	private final def performPaste() {
		var clipboard = (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
		var cr = contentResolver
		var clip = clipboard.primaryClip
		if (clip !== null) {
			var String text = null
			var String title = null
			var item = clip.getItemAt(0)
			var uri = item.uri
			if (uri !== null && NotePad.CONTENT_ITEM_TYPE == cr.getType(uri)) {
				var orig = cr.query(uri, PROJECTION, null, null, null)
				if (orig !== null) {
					if (orig.moveToFirst) {
						var colNoteIndex = mCursor.getColumnIndex(NotePad.COLUMN_NAME_NOTE)
						var colTitleIndex = mCursor.getColumnIndex(NotePad.COLUMN_NAME_TITLE)
						text = orig.getString(colNoteIndex)
						title = orig.getString(colTitleIndex)
					}
					orig.close
				}
			}
			if (text === null) {
				text = item.coerceToText(this).toString
			}
			updateNote(text, title)
		}
	}

	/** 
	 * Replaces the current note contents with the text and title provided as arguments.
	 * @param text The new note contents to use.
	 * @param title The new note title to use
	 */
	private final def updateNote(String text, String theTitle) {
		var title = theTitle
		var values = new ContentValues()
		values.put(NotePad.COLUMN_NAME_MODIFICATION_DATE, System.currentTimeMillis)
		if (mState === STATE_INSERT) {
			if (title === null) {
				var length = text.length
				title = text.substring(0, Math.min(30, length))
				if (length > 30) {
					var lastSpace = title.lastIndexOf(' ')
					if (lastSpace > 0) {
						title = title.substring(0, lastSpace)
					}
				}
			}
			values.put(NotePad.COLUMN_NAME_TITLE, title)
		} else if (title !== null) {
			values.put(NotePad.COLUMN_NAME_TITLE, title)
		}
		values.put(NotePad.COLUMN_NAME_NOTE, text)
		contentResolver.update(mUri, values, null, null)
	}

	/** 
	 * This helper method cancels the work done on a note.  It deletes the note if it was
	 * newly created, or reverts to the original text of the note i
	 */
	private final def cancelNote() {
		if (mCursor !== null) {
			if (mState === STATE_EDIT) {
				mCursor.close
				mCursor = null
				var values = new ContentValues()
				values.put(NotePad.COLUMN_NAME_NOTE, mOriginalContent)
				contentResolver.update(mUri, values, null, null)
			} else if (mState === STATE_INSERT) {
				deleteNote
			}
		}
		result = RESULT_CANCELED
		finish
	}

	/** 
	 * Take care of deleting a note.  Simply deletes the entry.
	 */
	private final def deleteNote() {
		if (mCursor !== null) {
			mCursor.close
			mCursor = null
			contentResolver.delete(mUri, null, null)
			mText.text = ''
		}
	}
}
