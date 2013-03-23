;;; syslog-mode.el --- Mode for viewing system logfiles
;;
;; ~harley/share/emacs/pkg/syslog-mode.el ---
;;
;; $Id: syslog-mode.el,v 1.7 2003/03/17 18:50:12 harley Exp $
;;

;; Author:    Harley Gorrell <harley@mahalito.net>
;; URL:       http://www.mahalito.net/~harley/elisp/syslog-mode.el
;; License:   GPL v2
;; Keywords:  syslog, emacs

;;; Commentary:
;; * Handy functions for looking at system logs.
;; * Fontifys the date and su messages.

;;; History:
;; 20-Mar-2013    Christian Giménez
;;    Added more keywords for font-lock.
;;  2003-03-16 : Updated URL and contact info.
;; 21-Mar-2013    Joe Bloggs
;;    Added functions and keybindings for filtering
;;    lines by regexps or dates, and for highlighting,
;;    and quick key for find-file-at-point

;; If anyone wants to make changes please fork the following github repo: https://github.com/vapniks/syslog-mode

;;; TODO: statistical reporting - have a regular expression to match item type, then report counts of each item type.
;;        also statistics on number of items per hour/day/week/etc.


;;; Require
(require 'hide-lines)

;;; Code:

;; Setup
(defgroup syslog nil
  "syslog-mode - a major mode for viewing log files"
  :link '(url-link "https://github.com/vapniks/syslog-mode"))

(defvar syslog-mode-hook nil
  "*Hook to setup `syslog-mode'.")

(defvar syslog-mode-load-hook nil
  "*Hook to run when `syslog-mode' is loaded.")

;;;###autoload
(defvar syslog-setup-on-load nil
  "*If not nil setup syslog mode on load by running syslog-add-hooks.")

;; I also use "Alt" as C-c is too much to type for cursor motions.
(defvar syslog-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Ctrl bindings
    (define-key map [C-down] 'syslog-boot-start)
    (define-key map "R" 'revert-buffer)
    (define-key map "/" 'syslog-filter-lines)
    (define-key map "g" 'show-all-invisible)
    (define-prefix-command 'syslog-highlight-map)
    (define-key map "h" 'syslog-highlight-map)
    (define-key map (kbd "h r") 'highlight-regexp)
    (define-key map (kbd "h p") 'highlight-phrase)
    (define-key map (kbd "h l") 'highlight-lines-matching-regexp)
    (define-key map (kbd "h u") 'unhighlight-regexp)
    (define-key map (kbd "C-/") 'syslog-filter-dates)
    (define-key map "D" (lambda nil (interactive) (dired "/var/log")))
    (define-key map "j" 'ffap)
    (define-key map "<" 'syslog-previous-file)
    (define-key map ">" 'syslog-next-file)
    ;; XEmacs does not like the Alt bindings
    (if (string-match "XEmacs" (emacs-version))
	t)
    map)
  "The local keymap for `syslog-mode'.")

(defun syslog-previous-file (&optional arg)
  "Open the previous logfile backup, or the next one if a prefix arg is used.
Unix systems keep backups of log files with numbered suffixes, e.g. syslog.1 syslog.2.gz, etc.
where higher numbers indicate older log files.
This function will load the previous log file to the current one (if it exists), or the next
one if ARG is non-nil."
  (interactive "P")
  (let* ((res (string-match "\\(.*?\\)\\.\\([0-9]+\\)\\(\\.t?gz\\)?" buffer-file-name))
         (basename (if res (match-string 1 buffer-file-name)
                     buffer-file-name))
         (str (and res (match-string 2 buffer-file-name)))
         (curver (or (and str (string-to-number str)) 0))
         (nextver (if arg (1- curver) (1+ curver)))
         (nextfile (if (> nextver 0)
                       (concat basename "." (number-to-string nextver))
                     basename)))
    (if (file-readable-p nextfile)
        (find-file nextfile)
      (if (file-readable-p (concat nextfile ".gz"))
          (find-file (concat nextfile ".gz"))))))

(defun syslog-next-file nil
  "Open the next logfile.
This just calls `syslog-previous-file' with non-nil argument, so we can bind it to a key."
  (interactive)
  (syslog-previous-file t))

;;;###autoload
(defun syslog-filter-lines (&optional arg)
  "Restrict buffer to lines matching regexp.
With prefix arg: remove lines matching regexp."
  (interactive "p")
  (if (> arg 1)
      (let ((regex (read-regexp "Regexp matching lines to remove")))
        (unless (string= regex "")
          (hide-matching-lines regex)))
    (let ((regex (read-regexp "Regexp matching lines to keep")))
        (unless (string= regex "")
          (hide-non-matching-lines regex)))))

;;;###autoload
(defcustom syslog-datetime-regexp "^[a-z]\\{3\\} [0-9]\\{1,2\\} \\([0-9]\\{2\\}:\\)\\{2\\}[0-9]\\{2\\} "
  "A regular expression matching the date-time at the beginning of each line in the log file."
  :group 'syslog
  :type 'regexp)

;;;###autoload
(defun* syslog-date-to-time (date &optional safe)
  "Convert DATE string to time.
If no year is present in the date then the current year is used.
If DATE can't be parsed then if SAFE is non-nil return nil otherwise throw an error."
  (if safe
      (let ((time (safe-date-to-time (concat date " " (substring (current-time-string) -4)))))
        (if (and (= (car time) 0) (= (cdr time) 0))
            nil
          time))
    (date-to-time (concat date " " (substring (current-time-string) -4)))))

;;;###autoload
(defun syslog-filter-dates (start end &optional arg)
  "Restrict buffer to lines between dates.
With prefix arg: remove lines between dates."
  (interactive (let (firstdate lastdate)
                 (save-excursion
                   (goto-char (point-min))
                   (beginning-of-line)
                   (re-search-forward syslog-datetime-regexp nil t)
                   (setq firstdate (match-string 0))
                   (goto-char (point-max))
                   (beginning-of-line)
                   (re-search-backward syslog-datetime-regexp nil t)
                   (setq lastdate (match-string 0)))
                 (list (syslog-date-to-time (read-string "Start date and time: "
                                                         firstdate nil firstdate))
                       (syslog-date-to-time (read-string "End date and time: "
                                                         lastdate nil lastdate))
                     current-prefix-arg)))
  (set (make-local-variable 'line-move-ignore-invisible) t)
  (goto-char (point-min))
  (let* ((start-position (point-min))
         (pos (re-search-forward syslog-datetime-regexp nil t))
         (intime-p (if arg (lambda (time)
                             (and time (not (and (time-less-p time end)
                                                 (not (time-less-p time start))))))
                     (lambda (time)
                       (and time (and (time-less-p time end)
                                      (not (time-less-p time start)))))))
         (keeptime (funcall intime-p (syslog-date-to-time (match-string 0) t)))
         (dodelete t))
    (while pos
      (cond ((and keeptime dodelete)
             (add-invisible-overlay start-position (point-at-bol))
             (setq dodelete nil))
            ((not (or keeptime dodelete))
             (setq dodelete t start-position (point-at-bol))))
      (setq pos (re-search-forward syslog-datetime-regexp nil t)
            keeptime (funcall intime-p (syslog-date-to-time (match-string 0) t))))
    (if dodelete (add-invisible-overlay start-position (point-max)))))

;;;###autoload
(defun syslog-mode ()
  "Major mode for working with system logs.

\\{syslog-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (setq mode-name "syslog")
  (setq major-mode 'syslog-mode)
  (use-local-map syslog-mode-map)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '(syslog-font-lock-keywords))
  (run-hooks 'syslog-mode-hook))

(defvar syslog-boot-start-regexp "unix: SunOS"
  "Regexp to match the first line of boot sequence.")

(defun syslog-boot-start ()
  "Jump forward in the log to when the system booted."
  (interactive)
  (search-forward-regexp syslog-boot-start-regexp (point-max) t)
  (beginning-of-line))

(defvar syslog-ip-face 'syslog-ip-face)

(defcustom syslog-ip-face
  '((t :underline t :slant italic :weight bold))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

(defcustom syslog-hour-face
  '((t :weight bold  :inherit font-lock-type-face))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

(defcustom syslog-error-face
  '((t  :weight bold :foreground "red"))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

(defcustom syslog-warn-face
  '((t  :weight bold :foreground "goldenrod"))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

(defcustom syslog-info-face
  '((t  :weight bold :foreground "deep sky blue"))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)


(defcustom syslog-debug-face
  '((t  :weight bold :foreground "medium spring green"))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

(defcustom syslog-su-face
  '((t  :weight bold :foreground "firebrick"))
  "Face for IPs"
  :group 'syslog
  :type 'sexp)

;; Keywords
;; Todo: Seperate the keywords into a list for each format, rather
;; than one for all.
(defvar syslog-font-lock-keywords
  '(
    ;; Hours: 17:36:00 
    ("\\(?:^\\|[[:space:]]\\)\\([[:digit:]]\\{1,2\\}:[[:digit:]]\\{1,2\\}\\(:[[:digit:]]\\{1,2\\}\\)?\\)\\(?:$\\|[[:space:]]\\)" . (1 syslog-hour-face append))
    ;; Date
    ("\\(?:^\\|[[:space:]]\\)\\([[:digit:]]\\{1,2\\}/[[:digit:]]\\{1,2\\}/[[:digit:]]\\{2,4\\}\\)\\(?:$\\|[[:space:]]\\)" . (1 syslog-hour-face append))
    ;; Dates: May  9 15:52:34
    ("^\\(\\(?:[[:alpha:]]\\{3\\}\\)?[[:space:]]*[[:alpha:]]\\{3\\}\\s-+[0-9]+\\s-+[0-9:]+\\)" (1 font-lock-type-face t))
    ;; Su events
    ("\\(su:.*$\\)" . (1 syslog-su-face t))
    ("\\(sudo:.*$\\)" . (1 syslog-su-face t))    
    ("\\[[^]]*\\]" . 'font-lock-comment-face)
    ;; IPs
    ("[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}\\.[[:digit:]]\\{1,3\\}" (0 syslog-ip-face append))
    ("[Ee][Rr][Rr]\\(?:[Oo][Rr]\\)?" . (0 syslog-error-face append))
    ("[Ii][Nn][Ff][Oo]" . (0 syslog-info-face append))
    ("STARTUP" . (0 syslog-info-face append))
    ("CMD" . (0 syslog-info-face append))
    ("[Ww][Aa][Rr][Nn]\\(?:[Ii][Nn][Gg]\\)?" . (0 syslog-warn-face append))
    ("[Dd][Ee][Bb][Uu][Gg]" . (0 syslog-debug-face append))
    ("(EE)" . (0 syslog-error-face append))
    ("(WW)" . (0 syslog-warn-face append))
    ("(II)" . (0 syslog-info-face append))
    ("(NI)" . (0 syslog-warn-face append))
    ("(!!)" . (0 syslog-debug-face append))
    ("(--)" . (0 syslog-debug-face append))
    ("(\\*\\*)" . (0 syslog-debug-face append))
    ("(==)" . (0 syslog-debug-face append))
    ("(\\+\\+)" . (0 syslog-debug-face append)))
  "Expressions to hilight in `syslog-mode'.")


;;; Setup functions
(defun syslog-find-file-func ()
  "Invoke `syslog-mode' if the buffer appears to be a system logfile.
and another mode is not active.
This function is added to `find-file-hooks'."
  (if (and (eq major-mode 'fundamental-mode)
	   (looking-at syslog-sequence-start-regexp))
      (syslog-mode)))

(defun syslog-add-hooks ()
  "Add a default set of syslog-hooks.
These hooks will activate `syslog-mode' when visiting a file
which has a syslog-like name (.fasta or .gb) or whose contents
looks like syslog.  It will also turn enable fontification for `syslog-mode'."
  ;; (add-hook 'find-file-hooks 'syslog-find-file-func)
  (add-to-list
   'auto-mode-alist
   '("\\(messages\\(\\.[0-9]\\)?\\|SYSLOG\\)\\'" . syslog-mode)))

;; Setup hooks on request when this mode is loaded.
(if syslog-setup-on-load
    (syslog-add-hooks))

;; done loading
(run-hooks 'syslog-mode-load-hook)
(provide 'syslog-mode)

;;; syslog-mode.el ends here

;;; (yaoddmuse-post "EmacsWiki" "syslog-mode.el" (buffer-name) (buffer-string) "update")
