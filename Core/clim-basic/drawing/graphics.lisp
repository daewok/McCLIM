;;; ---------------------------------------------------------------------------
;;;   License: LGPL-2.1+ (See file 'Copyright' for details).
;;; ---------------------------------------------------------------------------
;;;
;;;  (c) copyright 1998-2003 Michael McDonald <mikemac@mikemac.com>
;;;  (c) copyright 2001 Arnaud Rouanet <rouanet@emi.u-bordeaux.fr>
;;;  (c) copyright 2001,2002 Alexey Dejneka
;;;  (c) copyright 2002 Brian Spilsbury
;;;  (c) copyright 2002,2003 Gilbert Baumann <gbaumann@common-lisp.net>
;;;  (c) copyright 2003-2008 Andy Hefner <ahefner@common-lisp.net>
;;;  (c) copyright 2005,2006 Timothy Moore <tmoore@common-lisp.net>
;;;  (c) copyright 2005 Rudi Schlatte <rschlatte@common-lisp.net>
;;;  (c) copyright 2008 Troels Henriksen <thenriksen@common-lisp.net>
;;;  (c) copyright 2014 Robert Strandh <robert.strandh@gmail.com>
;;;  (c) copyright 2016 Alessandro Serra <gas2serra@gmail.com>
;;;  (c) copyright 2018 Elias Mårtenson <lokedhs@gmail.com>
;;;  (c) copyright 2019-2021 Jan Moringen <jmoringe@techfak.uni-bielefeld.de>
;;;  (c) copyright 2016-2021 Daniel Kochmański <daniel@turtleware.eu>
;;;
;;; ---------------------------------------------------------------------------
;;;
;;; Standard presentations types.
;;;

(in-package #:clim-internals)

;;; Work in progress that reduces consing of rest arguments and keyword
;;; processing.
(defmacro with-medium-and-options ((sheet
                                    &key ink clipping-region transformation
                                    line-unit line-thickness
                                    line-style line-style-p
                                    line-dashes dashes-p
                                    line-joint-shape line-cap-shape
                                    text-style text-style-p
                                    text-family text-family-p
                                    text-face text-face-p
                                    text-size text-size-p)
                                   (medium)
                                   &body body)
  (with-gensyms (continuation sheet-medium)
    `(flet ((,continuation (,medium)
              ,@body))
       (declare (dynamic-extent #',continuation))
       (with-sheet-medium (,sheet-medium ,sheet)
         (do-graphics-with-options-internal-1
             ,sheet-medium #'continuation
             ,ink ,clipping-region ,transformation
             ,line-unit ,line-thickness
             ,line-style ,line-style-p
             ,line-dashes ,dashes-p
             ,line-joint-shape ,line-cap-shape
             ,text-style ,text-style-p
             ,text-family ,text-family-p
             ,text-face ,text-face-p
             ,text-size ,text-size-p)))))

(defgeneric do-graphics-with-options-internal
  (medium orig-medium func
          &rest args
          &key
          ink clipping-region transformation
          line-unit line-thickness line-style line-dashes
          line-join-shape line-cap-shape
          text-style text-family text-face text-size
          &allow-other-keys))

;;; The generic function DO-GRAPHICS-WITH-OPTIONS is internal to the
;;; CLIM-INTERNALS package.  It is used in the expansion of the macro
;;; WITH-MEDIUM-OPTIONS.
(defgeneric do-graphics-with-options (medium function &rest options))

(defmethod do-graphics-with-options ((sheet sheet) func &rest options)
  (with-sheet-medium (medium sheet)
    (let ((*foreground-ink* (medium-foreground medium))
          (*background-ink* (medium-background medium)))
      (apply #'do-graphics-with-options-internal medium sheet func options))))

(defmethod do-graphics-with-options ((medium medium) func &rest options)
  (let ((*foreground-ink* (medium-foreground medium))
        (*background-ink* (medium-background medium)))
    (apply #'do-graphics-with-options-internal medium medium func options)))

(defmethod do-graphics-with-options ((sheet t) func &rest options)
  (declare (ignore options))
  (when sheet
    (funcall func sheet)))

(defmethod do-graphics-with-options-internal ((medium medium) orig-medium func
                                     &rest args
                                     &key ink clipping-region transformation
                                          line-unit line-thickness
                                          (line-style nil line-style-p)
                                          (line-dashes nil dashes-p)
                                          line-joint-shape line-cap-shape
                                          (text-style nil text-style-p)
                                          (text-family nil text-family-p)
                                          (text-face nil text-face-p)
                                          (text-size nil text-size-p)
                                     &allow-other-keys)
  (declare (ignore args))
  (let ((old-ink (medium-ink medium))
        (old-clip (medium-clipping-region medium))
        (old-transform (medium-transformation medium))
        (old-line-style (medium-line-style medium))
        (old-text-style (medium-text-style medium))
        (changed-line-style line-style-p)
        (changed-text-style text-style-p))
    (unwind-protect
        (progn
          (when (eq ink old-ink) (setf ink nil))

          (when ink
              (setf (medium-ink medium) ink))
          (when transformation
              (setf (medium-transformation medium)
                (compose-transformations old-transform transformation)))

          (when (and clipping-region old-clip
                     (or (eq clipping-region +everywhere+)
                         (eq clipping-region old-clip)
                         (region-contains-region-p clipping-region old-clip))
                     #+NIL (region-equal clipping-region old-clip))
            (setf clipping-region nil))

          (when clipping-region
            (setf (medium-clipping-region medium)
                  (region-intersection
                   (if transformation
                       (transform-region transformation old-clip)
                       old-clip)
                   clipping-region)))
          (when (null line-style)
              (setf line-style old-line-style))
          (when (or line-unit
                    line-thickness
                    dashes-p
                    line-joint-shape
                    line-cap-shape)
            (setf changed-line-style t)
            (setf line-style
                  (make-line-style
                   :unit (or line-unit
                             (line-style-unit line-style))
                   :thickness (or line-thickness
                                  (line-style-thickness line-style))
                   :dashes (if dashes-p
                               line-dashes
                               (line-style-dashes line-style))
                   :joint-shape (or line-joint-shape
                                    (line-style-joint-shape line-style))
                   :cap-shape (or line-cap-shape
                                  (line-style-cap-shape line-style)))))
          (when changed-line-style
            (setf (medium-line-style medium) line-style))
          (if text-style-p
              (setf text-style
                    (merge-text-styles text-style
                                       (medium-merged-text-style medium)))
              (setf text-style (medium-merged-text-style medium)))
          (when (or text-family-p text-face-p text-size-p)
            (setf changed-text-style t)
            (setf text-style (merge-text-styles (make-text-style text-family
                                                                 text-face
                                                                 text-size)
                                                text-style)))
          (when changed-text-style
            (setf (medium-text-style medium) text-style))

          (when orig-medium
            (funcall func orig-medium)))

      (when ink
        (setf (medium-ink medium) old-ink))
      ;; First set transformation, then clipping!
      (when transformation
        (setf (medium-transformation medium) old-transform))
      (when clipping-region
        (setf (medium-clipping-region medium) old-clip))
      (when changed-line-style
        (setf (medium-line-style medium) old-line-style))
      (when changed-text-style
        (setf (medium-text-style medium) old-text-style)))))

(defmacro with-medium-options ((sheet args)
                               &body body)
  `(flet ((graphics-op (medium)
            (declare (ignorable medium))
            ,@body))
     (declare (dynamic-extent #'graphics-op))
     (apply #'do-graphics-with-options ,sheet #'graphics-op ,args)))

(defmacro with-drawing-options ((medium &rest drawing-options) &body body)
  (setq medium (stream-designator-symbol medium '*standard-output*))
  (with-gensyms (gcontinuation cont-arg)
    `(flet ((,gcontinuation (,cont-arg)
              (declare (ignore ,cont-arg))
              ,@body))
       (declare (dynamic-extent #',gcontinuation))
       (invoke-with-drawing-options
        ,medium #',gcontinuation ,@drawing-options))))

(defmethod invoke-with-drawing-options ((medium medium) continuation
                                        &rest drawing-options
                                        &key ink transformation clipping-region
                                        line-style text-style
                                        &allow-other-keys)
  (declare (ignore ink transformation clipping-region line-style text-style))
  (with-medium-options (medium drawing-options)
    (funcall continuation medium)))

(defmethod invoke-with-drawing-options ((sheet sheet) continuation
                                        &rest drawing-options)
  (with-sheet-medium (medium sheet)
    (with-medium-options (medium drawing-options)
      ;; We need to pass SHEET to CONTINUATION (not MEDIUM, like we
      ;; used to) so that output recording works.
      (funcall continuation sheet))))

;;; Compatibility with real CLIM
(defmethod invoke-with-drawing-options ((medium t) continuation
                                        &rest drawing-options)
  (declare (ignore drawing-options))
  (funcall continuation medium))

(defmethod invoke-with-identity-transformation
    ((sheet sheet) continuation)
  (with-sheet-medium (medium sheet)
    (letf (((medium-transformation medium) +identity-transformation+))
      (funcall continuation sheet))))

(defmethod invoke-with-identity-transformation
    ((medium medium) continuation)
  (letf (((medium-transformation medium) +identity-transformation+))
    (funcall continuation medium)))

(defmethod invoke-with-local-coordinates (medium cont x y)
  ;; For now we do as real CLIM does.
  ;; Default seems to be the cursor position.
  ;; Moore suggests we use (0,0) if medium is no stream.
  ;;
  ;; Furthermore, the specification is vague about possible scalings ...
  (unless (and x y)
    (multiple-value-bind (cx cy) (if (extended-output-stream-p medium)
                                     (stream-cursor-position medium)
                                     (values 0 0))
      (setf x (or x cx)
            y (or y cy))))
  (multiple-value-bind (mxx mxy myy myx tx ty)
      (get-transformation (medium-transformation medium))
    (declare (ignore tx ty))
    (with-identity-transformation (medium)
      (with-drawing-options
          (medium :transformation (make-transformation
                                   mxx mxy myy myx
                                   x y))
        (funcall cont medium)))))

(defmethod invoke-with-first-quadrant-coordinates (medium cont x y)
  ;; First we do the same as invoke-with-local-coordinates but rotate and deskew
  ;; it so that it becomes first-quadrant. We do this by simply measuring the
  ;; length of the transformed x and y "unit vectors".  [That is (0,0)-(1,0) and
  ;; (0,0)-(0,1)] and setting up a transformation which features an upward
  ;; pointing y-axis and a right pointing x-axis with a length equal to above
  ;; measured vectors.
  (unless (and x y)
    (multiple-value-bind (cx cy) (if (extended-output-stream-p medium)
                                     (stream-cursor-position medium)
                                     (values 0 0))
      (setf x (or x cx)
            y (or y cy))))
  (let* ((tr (medium-transformation medium))
         (xlen
          (multiple-value-bind (dx dy) (transform-distance tr 1 0)
            (sqrt (+ (expt dx 2) (expt dy 2)))))
         (ylen
          (multiple-value-bind (dx dy) (transform-distance tr 0 1)
            (sqrt (+ (expt dx 2) (expt dy 2))))))
    (with-identity-transformation (medium)
      (with-drawing-options
          (medium :transformation (make-transformation
                                   xlen 0 0 (- ylen)
                                   x y))
        (funcall cont medium)))))

;;; 10.3 Line Styles

;;; 10.3.2 Contrasting Dash Patterns

(defconstant +contrasting-dash-patterns+
  ;; Must be at least eight according to the specification (Section
  ;; 10.3.2 Contrasting Dash Patterns).
  #(#(2 2) #(2 4)     #(2 8)     #(2 16) ; dots with varying empty space
           #(4 2)     #(8 2)     #(16 2) ; varying dashes with minimum empty space
           #(2 2 4 2) #(2 2 8 2)))       ; mixed

(defmethod contrasting-dash-pattern-limit (port)
  (length +contrasting-dash-patterns+))

(defun make-contrasting-dash-patterns (n &optional k)
  (let ((contrasting-dash-patterns +contrasting-dash-patterns+))
    (unless (<= 1 n (length contrasting-dash-patterns))
      (error "The argument N = ~D is out of range [1, ~D]"
             n (length contrasting-dash-patterns)))
    (unless (or (null k) (<= 0 k (1- n)))
      (error "The argument K = ~D is out of range [0, ~D]" k (1- n)))
    (if (null k)
        (subseq contrasting-dash-patterns 0 n)
        (aref contrasting-dash-patterns k))))

;;; 12 Graphics

(defun draw-point (sheet point
                   &rest args
                   &key ink clipping-region transformation
                        line-style line-thickness line-unit)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness line-unit))
  (with-medium-options (sheet args)
    (multiple-value-bind (x y) (point-position point)
      (medium-draw-point* medium x y))))

(defun draw-point* (sheet x y
                    &rest args
                    &key ink clipping-region transformation
                         line-style line-thickness line-unit)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness line-unit))
  (with-medium-options (sheet args)
    (medium-draw-point* medium x y)))

(defun expand-point-seq (point-seq)
  (let ((coord-seq nil))
    (do-sequence (point point-seq)
      (multiple-value-bind (x y) (point-position point)
        (setq coord-seq (list* y x coord-seq))))
    (nreverse coord-seq)))

(defun draw-points (sheet point-seq
                    &rest args
                    &key ink clipping-region transformation
                         line-style line-thickness line-unit)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness line-unit))
  (with-medium-options (sheet args)
    (medium-draw-points* medium (expand-point-seq point-seq))))

(defun draw-points* (sheet coord-seq
                     &rest args
                     &key ink clipping-region transformation
                          line-style line-thickness line-unit)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness line-unit))
  (with-medium-options (sheet args)
    (medium-draw-points* medium coord-seq)))

(defun draw-line (sheet point1 point2
                  &rest args
                  &key ink clipping-region transformation line-style
                    line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (multiple-value-bind (x1 y1) (point-position point1)
      (multiple-value-bind (x2 y2) (point-position point2)
        (medium-draw-line* medium x1 y1 x2 y2)))))

(defun draw-line* (sheet x1 y1 x2 y2
                   &rest args
                   &key ink clipping-region transformation line-style
                     line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-line* medium x1 y1 x2 y2)))

(defun draw-lines (sheet point-seq
                   &rest args
                   &key ink clipping-region transformation line-style
                     line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-lines* medium (expand-point-seq point-seq))))

(defun draw-lines* (sheet coord-seq
                    &rest args
                    &key ink clipping-region transformation line-style
                      line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-lines* medium coord-seq)))

(defun draw-polygon (sheet point-seq
                     &rest args
                     &key (filled t) (closed t) ink clipping-region
                       transformation line-style line-thickness
                       line-unit line-dashes line-joint-shape line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-polygon* medium (expand-point-seq point-seq) closed filled)))

(defun draw-polygon* (sheet coord-seq
                    &rest args
                    &key (filled t) (closed t) ink clipping-region
                      transformation line-style line-thickness line-unit
                      line-dashes line-joint-shape line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-polygon* medium coord-seq closed filled)))

(defun draw-rectangle (sheet point1 point2
                        &rest args
                        &key (filled t) ink clipping-region transformation
                          line-style line-thickness line-unit
                          line-dashes line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (with-medium-options (sheet args)
    (multiple-value-bind (x1 y1) (point-position point1)
      (multiple-value-bind (x2 y2) (point-position point2)
        (medium-draw-rectangle* medium x1 y1 x2 y2 filled)))))

(defun draw-rectangle* (sheet x1 y1 x2 y2
                        &rest args
                        &key (filled t) ink clipping-region transformation
                          line-style line-thickness line-unit line-dashes
                          line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (with-medium-options (sheet args)
    (medium-draw-rectangle* medium x1 y1 x2 y2 filled)))

(defun draw-rectangles (sheet points
                        &rest args
                        &key (filled t) ink clipping-region transformation
                          line-style line-thickness line-unit line-dashes
                          line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (with-medium-options (sheet args)
    (loop for point in points
          nconcing (multiple-value-bind (x y) (point-position point)
                     (list x y)) into position-seq
          finally (medium-draw-rectangles* medium position-seq filled))))

(defun draw-rectangles* (sheet position-seq
                         &rest args
                         &key (filled t) ink clipping-region transformation
                           line-style line-thickness line-unit
                           line-dashes line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (with-medium-options (sheet args)
    (medium-draw-rectangles* medium position-seq filled)))

(defun draw-triangle (sheet point1 point2 point3
                      &rest args
                      &key (filled t) ink clipping-region transformation
                        line-style line-thickness line-unit line-dashes
                        line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (apply #'draw-polygon sheet (list point1 point2 point3)
         :filled filled :closed t args))

(defun draw-triangle* (sheet x1 y1 x2 y2 x3 y3
                       &rest args
                       &key (filled t) ink clipping-region transformation
                         line-style line-thickness line-unit line-dashes
                         line-joint-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-joint-shape))
  (apply #'draw-polygon* sheet (list x1 y1 x2 y2 x3 y3)
         :filled filled :closed t args))

(defun draw-ellipse (sheet
                     center-point
                     radius-1-dx radius-1-dy radius-2-dx radius-2-dy
                     &rest args
                     &key (filled t) (start-angle 0.0) (end-angle (* 2.0 pi))
                       ink clipping-region transformation line-style
                       line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (multiple-value-bind (center-x center-y) (point-position center-point)
      (medium-draw-ellipse* medium
                            center-x center-y
                            radius-1-dx radius-1-dy radius-2-dx radius-2-dy
                            start-angle end-angle filled))))

(defun draw-ellipse* (sheet
                      center-x center-y
                      radius-1-dx radius-1-dy radius-2-dx radius-2-dy
                      &rest args
                      &key (filled t) (start-angle 0.0) (end-angle (* 2.0 pi))
                        ink clipping-region transformation line-style
                        line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-ellipse* medium
                          center-x center-y
                          radius-1-dx radius-1-dy radius-2-dx radius-2-dy
                          start-angle end-angle filled)))

(defun draw-circle (sheet
                    center-point radius
                    &rest args
                    &key (filled t) (start-angle 0.0) (end-angle (* 2.0 pi))
                      ink clipping-region transformation
                      line-style line-thickness line-unit line-dashes
                      line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (multiple-value-bind (center-x center-y) (point-position center-point)
      (medium-draw-ellipse* medium
                            center-x center-y
                            radius 0 0 radius
                            start-angle end-angle filled))))

(defun draw-circle* (sheet
                     center-x center-y radius
                     &rest args
                     &key (filled t) (start-angle 0.0) (end-angle (* 2.0 pi))
                       ink clipping-region transformation line-style
                       line-thickness line-unit line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (medium-draw-ellipse* medium
                          center-x center-y
                          radius 0 0 radius
                          start-angle end-angle filled)))

(defun draw-text (sheet string point
                   &rest args
                   &key (start 0) (end nil)
                     (align-x :left) (align-y :baseline)
                     (toward-point nil toward-point-p)
                     transform-glyphs
                     ink clipping-region transformation
                     text-style text-family text-face text-size)
  (declare (ignore ink clipping-region transformation
                   text-style text-family text-face text-size))
  (with-medium-options (sheet args)
    (multiple-value-bind (x y) (point-position point)
      (multiple-value-bind (toward-x toward-y)
          (if toward-point-p
              (point-position toward-point)
              (values (1+ x) y))
        (medium-draw-text* medium string x y
                           start end
                           align-x align-y
                           toward-x toward-y transform-glyphs)))))

(defun draw-text* (sheet string x y
                   &rest args
                   &key (start 0) (end nil)
                     (align-x :left) (align-y :baseline)
                     (toward-x (1+ x)) (toward-y y) transform-glyphs
                     ink clipping-region transformation
                     text-style text-family text-face text-size)
  (declare (ignore ink clipping-region transformation
                   text-style text-family text-face text-size))
  (with-medium-options (sheet args)
    (medium-draw-text* medium string x y
                       start end
                       align-x align-y
                       toward-x toward-y transform-glyphs)))

(defun draw-arrow (sheet point-1 point-2
                   &rest args
                   &key ink clipping-region transformation
                        line-style line-thickness
                        line-unit line-dashes line-cap-shape
                        (to-head t) from-head (head-length 10) (head-width 5)
                        (head-filled nil) angle)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness
                   line-unit line-dashes line-cap-shape
                   to-head from-head head-length head-width
                   head-filled angle))
  (multiple-value-bind (x1 y1) (point-position point-1)
    (multiple-value-bind (x2 y2) (point-position point-2)
      (apply #'draw-arrow* sheet x1 y1 x2 y2 args))))

(defun draw-arrow* (sheet x1 y1 x2 y2
                    &rest args
                    &key ink clipping-region transformation
                         line-style line-thickness
                         line-unit line-dashes line-cap-shape
                         (to-head t) from-head (head-length 10) (head-width 5)
                         (head-filled nil) angle)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (with-medium-options (sheet args)
    (with-translation (sheet x2 y2)
      (unless angle
        (let ((dx (- x1 x2))
              (dy (- y1 y2)))
          (if (and (zerop dx)
                   (zerop dy))
              (setf angle 0.0)
              (setf angle (atan* dx dy)))))
      (with-rotation (sheet angle)
        (let* ((end 0.0)
               (start (sqrt (+ (expt (- x2 x1) 2)
                               (expt (- y2 y1) 2))))
               (p end)
               (q start)
               (line-style (medium-line-style sheet))
               ;; FIXME: I believe this thickness is in "line-style-units",
               ;; which are only coincidentally the same as pixel coorindates
               ;; on screen backends, using :normal units. There is no function
               ;; documented for converting the units to stream coordinates.
               (thickness (multiple-value-bind (dx dy)
                              (transform-distance
                               (invert-transformation
                                (medium-transformation sheet))
                               (line-style-thickness line-style)
                               0)
                            (sqrt (+ (* dx dx) (* dy dy)))))
               (width/2 (/ head-width 2))
               (a (atan (/ width/2 head-length)))
               (offset (if (and head-length (not (zerop head-length)))
                           (/ thickness (* 2 (sin a )))
                           0.0))
               (tip-to-peak (+ head-length
                               offset
                               (- (* thickness 0.5 (sin a)))))) ;; okay, a guess..
          (when (not head-filled)
            (when to-head   (incf p offset))
            (when from-head (decf q offset)))
          (if (and to-head
                   from-head
                   (< (abs (- start end)) (* 2 tip-to-peak)))
              (let ((width (* 0.5 (+ head-width thickness)
                              (/ (abs (- start end))
                                 (* 2 tip-to-peak)) )))
                (draw-polygon* sheet
                               (list end 0
                                     (/ start 2) width
                                     start 0
                                     (/ start 2) (- width))
                               :filled head-filled
                               :line-thickness 0))
              (progn
                (when to-head
                  (draw-polygon* sheet
                                 (list (+ p head-length) (- width/2)
                                       p 0
                                       (+ p head-length) width/2)
                                 :filled head-filled
                                 :closed nil))
                (when from-head
                  (draw-polygon* sheet
                                 (list (- q head-length) (- width/2)
                                       q 0
                                       (- q head-length) width/2)
                                 :filled head-filled
                                 :closed nil))

                (unless (< q p)
                  (when head-filled
                    (when to-head   (incf p offset))
                    (when from-head (decf q offset)))
                  (draw-line* sheet q 0 p 0)))))))))

(defun draw-oval (sheet center-pt x-radius y-radius
                  &rest args
                  &key (filled t) ink clipping-region transformation
                    line-style line-thickness line-unit
                    line-dashes line-cap-shape)
  (declare (ignore filled ink clipping-region transformation
                   line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (multiple-value-bind (x1 y1) (point-position center-pt)
    (apply #'draw-oval* sheet x1 y1 x-radius y-radius args)))

(defun draw-oval* (sheet center-x center-y x-radius y-radius
                   &rest args
                   &key (filled t) ink clipping-region transformation
                     line-style line-thickness line-unit
                     line-dashes line-cap-shape)
  (declare (ignore ink clipping-region transformation
                   line-style line-thickness
                   line-unit line-dashes line-cap-shape))
  (check-type x-radius (real 0))
  (check-type y-radius (real 0))
  (with-medium-options (sheet args)
    (if (or (coordinate= x-radius 0) (coordinate= y-radius 0))
        (draw-circle* sheet center-x center-y (max x-radius y-radius)
                      :filled filled)
        (if (coordinate<= y-radius x-radius)
            (let ((x1 (- center-x x-radius)) (x2 (+ center-x x-radius))
                  (y1 (- center-y y-radius)) (y2 (+ center-y y-radius)))
              (if filled
                  ;; Kludge coordinates, sometimes due to rounding the
                  ;; lines don't connect.
                  (draw-rectangle* sheet (floor x1) y1 (ceiling x2) y2)
                  (draw-lines* sheet (list (floor x1) y1 (ceiling x2) y1
                                           (floor x1) y2 (ceiling x2) y2)))
              (draw-circle* sheet x1 center-y y-radius
                            :filled filled
                            :start-angle (* pi 0.5)
                            :end-angle (* pi 1.5))
              (draw-circle* sheet x2 center-y y-radius
                            :filled filled
                            :start-angle (* pi 1.5)
                            :end-angle (* pi 2.5)))
            (with-rotation (sheet (/ pi 2) (make-point center-x center-y))
              (draw-oval* sheet center-x center-y y-radius x-radius
                          :filled filled)) ))))


;;; Pixmap functions

(defmethod allocate-pixmap ((sheet sheet) width height)
  (with-sheet-medium (medium sheet)
    (allocate-pixmap medium width height)))

(defmethod allocate-pixmap ((medium medium) width height)
  (declare (ignore medium width height))
  (error "Don't know how to allocate a pixmap for a generic medium"))

(defmethod deallocate-pixmap (pixmap)
  (error "Don't know how to deallocate a pixmap of class ~s" (class-of pixmap)))


(defmethod copy-to-pixmap ((medium medium) medium-x medium-y width height
                           &optional pixmap (pixmap-x 0) (pixmap-y 0))
  (unless pixmap
    (setq pixmap (allocate-pixmap medium (+ pixmap-x width) (+ pixmap-y height))))
  (medium-copy-area medium medium-x medium-y width height
                    pixmap pixmap-x pixmap-y)
  pixmap)

(defmethod copy-to-pixmap ((sheet sheet) sheet-x sheet-y width height
                           &optional pixmap (pixmap-x 0) (pixmap-y 0))
  (copy-to-pixmap (sheet-medium sheet) sheet-x sheet-y width height
                  pixmap pixmap-x pixmap-y))

(defmethod copy-from-pixmap (pixmap pixmap-x pixmap-y width height
                             (medium medium) medium-x medium-y)
  (medium-copy-area pixmap pixmap-x pixmap-y width height
                    medium medium-x medium-y)
  pixmap)

(defmethod copy-from-pixmap (pixmap pixmap-x pixmap-y width height
                             (sheet sheet) sheet-x sheet-y)
  (medium-copy-area pixmap pixmap-x pixmap-y width height
                    (sheet-medium sheet) sheet-x sheet-y))

(defmethod copy-area ((medium medium) from-x from-y width height to-x to-y)
  (medium-copy-area medium from-x from-y width height
                    medium to-x to-y))

(defmethod copy-area ((sheet sheet) from-x from-y width height to-x to-y)
  (copy-area (sheet-medium sheet) from-x from-y width height to-x to-y))

(defmethod copy-area ((stream stream) from-x from-y width height to-x to-y)
  (if (sheetp stream)
      (copy-area (sheet-medium stream) from-x from-y width height to-x to-y)
    (error "COPY-AREA on a stream is not implemented")))

(defmacro with-output-to-pixmap ((medium-var sheet &key width height) &body body)
  (alexandria:once-only (sheet width height)
    (if (and width height)
        (alexandria:with-gensyms (pixmap port)
          `(let* ((,pixmap (allocate-pixmap ,sheet ,width ,height))
                  (,port (port ,sheet))
                  (,medium-var (make-medium ,port ,sheet)))
             (degraft-medium ,medium-var ,port ,sheet)
             (letf (((medium-drawable ,medium-var) ,pixmap)
                    ((medium-clipping-region ,medium-var)
                     (make-rectangle* 0 0 ,width ,height)))
               ,@body)
             ,pixmap))
        (let ((record (gensym "OUTPUT-RECORD-")))
          ;; What to do when only width or height are given?  And what's the
          ;; meaning of medium-var? -- rudi 2005-09-05
          `(let* ((,medium-var ,sheet)
                  (,record (with-output-to-output-record (,medium-var)
                             ,@body)))
             (with-output-to-pixmap
                 (,medium-var
                  ,sheet
                  :width ,(or width `(bounding-rectangle-width ,record))
                  :height ,(or height `(bounding-rectangle-height ,record)))
               (replay-output-record ,record ,medium-var)))))))


;;; Generic graphic operation methods

(defmacro def-sheet-trampoline (name (&rest args))
  (with-gensyms (stream medium)
    `(defmethod ,name ((,stream sheet) ,@args)
       (with-sheet-medium (,medium ,stream)
         (,name ,medium ,@args)))))

(defmacro def-graphic-op (name (&rest args))
  (let ((method-name (symbol-concat '#:medium- name '*)))
    `(eval-when (:execute :load-toplevel :compile-toplevel)
       (def-sheet-trampoline ,method-name ,args))))

(def-graphic-op draw-point (x y))
(def-graphic-op draw-points (coord-seq))
(def-graphic-op draw-line (x1 y1 x2 y2))
(def-graphic-op draw-lines (coord-seq))
(def-graphic-op draw-polygon (coord-seq closed filled))
(def-graphic-op draw-rectangle (left top right bottom filled))
(def-graphic-op draw-rectangles (position-seq filled))
(def-graphic-op draw-ellipse (center-x center-y
                                  radius-1-dx radius-1-dy radius-2-dx radius-2-dy
                                  start-angle end-angle filled))
(def-graphic-op draw-circle (center-x center-y radius start-angle end-angle filled))
(def-graphic-op draw-text (string x y
                               start end
                               align-x align-y
                               toward-x toward-y transform-glyphs))

(def-sheet-trampoline medium-clear-area (left top right bottom))
(def-sheet-trampoline medium-finish-output ())
(def-sheet-trampoline medium-force-output ())
(def-sheet-trampoline medium-beep ())

;;;
;;; DRAW-DESIGN
;;

(defmethod draw-design (medium (design point)
                        &rest options &key &allow-other-keys)
  (apply #'draw-point* medium (point-x design) (point-y design) options))

(defmethod draw-design (medium (design polyline)
                        &rest options &key &allow-other-keys)
  (apply #'draw-polygon medium (polygon-points design)
         :closed (polyline-closed design)
         :filled nil
         options))

(defmethod draw-design (medium (design polygon)
                        &rest options &key &allow-other-keys)
  (apply #'draw-polygon medium (polygon-points design)
         :filled t
         options))

(defmethod draw-design (medium (design line)
                        &rest options &key &allow-other-keys)
  (multiple-value-bind (x1 y1) (line-start-point* design)
    (multiple-value-bind (x2 y2) (line-end-point* design)
      (apply #'draw-line* medium x1 y1 x2 y2 options))))

(defmethod draw-design (medium (design rectangle)
                        &rest options &key &allow-other-keys)
  (multiple-value-bind (x1 y1 x2 y2) (rectangle-edges* design)
    (apply #'draw-rectangle* medium x1 y1 x2 y2 options)))

(defmethod draw-design (medium (design ellipse)
                        &rest options &key &allow-other-keys)
  (multiple-value-bind (cx cy) (ellipse-center-point* design)
    (multiple-value-bind (r1x r1y r2x r2y) (ellipse-radii design)
      (apply #'draw-ellipse* medium
             cx cy r1x r1y r2x r2y
             :start-angle (or (ellipse-start-angle design) 0.0)
             :end-angle (or (ellipse-end-angle design) (* 2.0 pi))
             options))))

(defmethod draw-design (medium (design elliptical-arc)
                        &rest options &key &allow-other-keys)
  (multiple-value-bind (cx cy) (ellipse-center-point* design)
    (multiple-value-bind (r1x r1y r2x r2y) (ellipse-radii design)
      (apply #'draw-ellipse* medium
             cx cy r1x r1y r2x r2y
             :start-angle (ellipse-start-angle design)
             :end-angle (ellipse-end-angle design)
             :filled nil
             options))))

(defmethod draw-design (medium (design standard-region-union)
                        &rest options &key &allow-other-keys)
  (map-over-region-set-regions (lambda (region)
                                 (apply #'draw-design medium region options))
                               design))

(defmethod draw-design (medium (design standard-rectangle-set)
                        &rest options &key &allow-other-keys)
  ;; ### we can do better (faster) than this.
  (map-over-region-set-regions (lambda (region)
                                 (apply #'draw-design medium region options))
                               design))

#+nyi
(defmethod draw-design (medium (design standard-region-intersection)
                        &rest options &key &allow-other-keys)
  )

#+nyi
(defmethod draw-design (medium (design standard-region-difference)
                        &rest options &key &allow-other-keys)
  )

(defmethod draw-design (medium (design (eql +nowhere+))
                        &rest options &key &allow-other-keys)
  (declare (ignore medium design options))
  nil)

(defmethod draw-design ((medium sheet) (design (eql +everywhere+))
                        &rest options &key &allow-other-keys)
  (apply #'draw-design
         medium (bounding-rectangle (sheet-region medium)) options))

(defmethod draw-design ((medium medium) (design (eql +everywhere+))
                        &rest options &key &allow-other-keys)
  (apply #'draw-design medium
         (bounding-rectangle (sheet-region (medium-sheet medium))) options))

;;;

(defmethod draw-design (medium (color color)
                        &rest options &key &allow-other-keys)
  (apply #'draw-design medium +everywhere+ :ink color options))

(defmethod draw-design (medium (color opacity)
                        &rest options &key &allow-other-keys)
  (apply #'draw-design medium +everywhere+ :ink color options))

(defmethod draw-design (medium (color standard-flipping-ink)
                        &rest options &key &allow-other-keys)
  (apply #'draw-design medium +everywhere+ :ink color options))

(defmethod draw-design (medium (color indirect-ink)
                        &rest options &key &allow-other-keys)
  (apply #'draw-design medium +everywhere+ :ink color options))

(defmethod draw-design (medium (pattern pattern)
                        &key clipping-region transformation &allow-other-keys)
  ;; It is said, that DRAW-PATTERN* performs only translation from the supplied
  ;; transformation. If we draw pattern with a DRAW-DESIGN we do apply full
  ;; transformation. That way we have open door for easy drawing transformed
  ;; patterns without compromising the specification. -- jd 2018-09-08
  (let ((width (pattern-width pattern))
        (height (pattern-height pattern)))
    (flet ((draw-it ()
             (draw-rectangle* medium 0 0 width height
                              :ink (transform-region (medium-transformation medium) pattern))))
      (if (or clipping-region transformation)
          (with-drawing-options (medium :clipping-region clipping-region
                                        :transformation  transformation)
            (draw-it))
          (draw-it)))))

(defmethod draw-design (medium (pattern transformed-pattern)
                        &key clipping-region transformation &allow-other-keys)
  (flet ((draw-it ()
           (let* ((effective-pattern (effective-transformed-design pattern))
                  (pattern-tr (transformed-design-transformation effective-pattern))
                  (pattern-ds (transformed-design-design effective-pattern))
                  (ink-tr (compose-transformations (medium-transformation medium) pattern-tr))
                  (width (pattern-width pattern-ds))
                  (height (pattern-height pattern-ds))
                  (region (transform-region pattern-tr (make-rectangle* 0 0 width height))))
             (draw-design medium region :ink (transform-region ink-tr pattern-ds)))))
    (if (or clipping-region transformation)
        (with-drawing-options (medium :clipping-region clipping-region
                                      :transformation  transformation)
          (draw-it))
        (draw-it))))

(defun draw-pattern* (medium pattern x y &key clipping-region transformation)
  ;; Note: I believe the sample implementation in the spec is incorrect. --GB
  ;; Note: It is just slightly incorrect - patterns are rectangular objects
  ;; aligned with XY axis. For drawing transformed designs we need to transform
  ;; said rectangular region hence we need to use DRAW-DESIGN. -- jd 2018-09-05
  (check-type pattern pattern)
  (labels ((draw (x y sx sy)
             ;; As I read the spec, the pattern itself is not transformed, so we
             ;; should draw the full (untransformed) pattern at the transformed x/y
             ;; coordinates. This requires we revert to the identity transformation
             ;; before drawing the rectangle. -Hefner
             (let* ((effective-pattern (effective-transformed-design pattern))
                    ;; Effective design
                    (effective-design  (transformed-design-design effective-pattern))
                    (design-rectangle  (make-rectangle*
                                        0 0
                                        (pattern-width effective-design)
                                        (pattern-height effective-design)))
                    ;; Effective pattern transformation
                    (pattern-transform (transformed-design-transformation
                                        effective-pattern))
                    (pattern-region    (transform-region
                                        pattern-transform design-rectangle))
                    ;; Final transformation and region. Adjust for
                    ;; offsets introduced by PATTERN-TRANSFORM and
                    ;; axis flipping introduced by the medium
                    ;; transformation.
                    (final-transform   (with-bounding-rectangle* (x1 y1 x2 y2)
                                           pattern-region
                                         (compose-transformations
                                          (make-translation-transformation
                                           (- x x1 (if (minusp sx) (- x2 x1) 0))
                                           (- y y1 (if (minusp sy) (- y2 y1) 0)))
                                          pattern-transform)))
                    (final-region      (transform-region
                                        final-transform design-rectangle))
                    (final-ink         (transform-region final-transform effective-design)))
               (with-identity-transformation (medium)
                 (draw-design medium final-region :ink final-ink))))
           (prepare-and-draw (transformation)
             ;; Capture the translation and axis-flipping aspects of
             ;; TRANSFORMATION.
             (multiple-value-bind (tx ty)
                 (transform-position transformation x y)
               (multiple-value-bind (sx sy)
                   (transform-distance transformation 1 1)
                 (draw tx ty (signum sx) (signum sy))))))
    (if (or clipping-region transformation)
        (with-drawing-options (medium :clipping-region clipping-region
                                      :transformation  transformation)
          (prepare-and-draw (medium-transformation medium)))
        (prepare-and-draw (medium-transformation medium)))))

(defun draw-rounded-rectangle* (sheet x1 y1 x2 y2
                                      &rest args &key
                                      (radius 7)
                                      (radius-x radius)
                                      (radius-y radius)
                                      (radius-left  radius-x)
                                      (radius-right radius-x)
                                      (radius-top    radius-y)
                                      (radius-bottom radius-y)
                                      filled &allow-other-keys)
  "Draw a rectangle with rounded corners"
  (apply #'invoke-with-drawing-options sheet
    (lambda (medium)
      (declare (ignore medium))
      (let ((medium sheet))
        (if (not (and (>= (- x2 x1) (* 2 radius-x))
                      (>= (- y2 y1) (* 2 radius-y))))
            (draw-rectangle* medium x1 y1 x2 y2)
            (with-grown-rectangle* ((ix1 iy1 ix2 iy2) (x1 y1 x2 y2)
                                    :radius-left   (- radius-left)
                                    :radius-right  (- radius-right)
                                    :radius-top    (- radius-top)
                                    :radius-bottom (- radius-bottom))
              (let ((zl (zerop radius-left))
                    (zr (zerop radius-right))
                    (zt (zerop radius-top))
                    (zb (zerop radius-bottom)))
                (if filled
                    (progn              ; Filled
                      (unless (or zl zt)
                        (draw-ellipse* medium
                                       ix1 iy1 radius-left
                                       0 0 radius-top
                                       :filled t))
                      (unless (or zr zt)
                        (draw-ellipse* medium
                                       ix2 iy1 radius-right
                                       0 0 radius-top
                                       :filled t))
                      (unless (or zl zb)
                        (draw-ellipse* medium
                                       ix1 iy2 radius-left
                                       0 0 radius-bottom
                                       :filled t))
                      (unless (or zr zb)
                        (draw-ellipse* medium
                                       ix2 iy2 radius-right
                                       0 0 radius-bottom
                                       :filled t))
                      (draw-rectangle* medium x1 iy1 x2 iy2 :filled t)
                      (draw-rectangle* medium ix1 y1 ix2 iy1 :filled t)
                      (draw-rectangle* medium ix1 iy2 ix2 y2 :filled t))
                    (progn              ; Unfilled
                      (unless (or zl zt)
                        (draw-ellipse* medium
                                       ix1 iy1 (- radius-left)
                                       0 0 (- radius-top)
                                       :start-angle (/ pi 2) :end-angle pi
                                       :filled nil))
                      (unless (or zr zt)
                        (draw-ellipse* medium
                                       ix2 iy1 (- radius-right)
                                       0 0 (- radius-top)
                                       :start-angle 0 :end-angle (/ pi 2)
                                       :filled nil))
                      (unless (or zl zb)
                        (draw-ellipse* medium
                                       ix1 iy2 (- radius-left)
                                       0 0 (- radius-bottom)
                                       :start-angle pi :end-angle (* 3/2 pi)
                                       :filled nil))
                      (unless (or zr zb)
                        (draw-ellipse* medium
                                       ix2 iy2 (- radius-right)
                                       0 0 (- radius-bottom)
                                       :start-angle (* 3/2 pi)
                                       :filled nil))
                      (labels ((fx (y p x1a x2a x1b x2b)
                                 (draw-line* medium
                                             (if p x1a x1b) y (if p x2a x2b) y))
                               (fy (x p y1a y2a y1b y2b)
                                 (draw-line* medium
                                             x (if p y1a y1b) x (if p y2a y2b))))
                        (fx y1 zt x1 x2 ix1 ix2)
                        (fy x1 zl y1 y2 iy1 iy2)
                        (fx y2 zb x1 x2 ix1 ix2)
                        (fy x2 zr y1 y2 iy1 iy2)))))))))
   (with-keywords-removed (args '(:radius :radius-x :radius-y
                                  :radius-left :radius-right
                                  :radius-top  :radius-bottom))
     args)))
